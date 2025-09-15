# app/services/progress_store.rb
# frozen_string_literal: true

# ШВИДКИЙ ProgressStore.
# - Лічильники: Redis HASH (HINCRBY)
# - Великі списки: Redis LIST (RPUSH/LRANGE/LTRIM)
# - Дедуп: Redis SET (SADD)
# - Оновлення: pipelined
#
class ProgressStore
  PREFIX         = "email_validation_job:"
  RESULTS_TAIL   = 50          # скільки останніх детальних записів зберігати
  TTL_SECONDS    = 3600

  class << self
    # ---- key helpers ----
    def key(job_id)         = "#{PREFIX}#{job_id}"        # HASH із лічильниками/метаданими
    def seen_key(job_id)    = "#{key(job_id)}:seen"       # SET нормалізованих емейлів
    def list_key(job_id, k) = "#{key(job_id)}:#{k}"       # LIST для великих масивів

    # ---- init / finish ----
    def init(job_id:, total: 0)
      RedisPool.with do |r|
        r.pipelined do
          r.call("DEL", key(job_id))
          r.call("DEL", seen_key(job_id))
          %w[valid_list invalid_list role_list duplicates_list results_list].each do |lname|
            r.call("DEL", list_key(job_id, lname))
          end

          initial = {
            "total"         => total.to_i,
            "processed"     => 0,
            "valid"         => 0,
            "invalid"       => 0,
            "done"          => 0,
            "role_rejected" => 0,
            "duplicates"    => 0
          }
          r.call("HMSET", key(job_id), *initial.flat_map { |k,v| [k, v] })

          # TTL на всі ключі
          r.call("EXPIRE", key(job_id), TTL_SECONDS)
          r.call("EXPIRE", seen_key(job_id), TTL_SECONDS)
          %w[valid_list invalid_list role_list duplicates_list results_list].each do |lname|
            r.call("EXPIRE", list_key(job_id, lname), TTL_SECONDS)
          end
        end
      end
    end

    def finish(job_id)
      RedisPool.with { |r| r.call("HSET", key(job_id), "done", 1) }
    end

    # ---- counters / totals ----
    def bump_total(job_id:, by:)
      RedisPool.with { |r| r.call("HINCRBY", key(job_id), "total", by.to_i) }
    end

    # ---- duplicates (SET) ----
    # true -> дублікат; false -> вперше
    def check_and_mark_seen(job_id:, email:)
      norm = email.to_s.strip.downcase
      RedisPool.with do |r|
        added = r.call("SADD", seen_key(job_id), norm)
        if added.to_i == 0
          r.pipelined do
            r.call("RPUSH", list_key(job_id, "duplicates_list"), email.to_s)
            r.call("HINCRBY", key(job_id), "processed", 1)
            r.call("HINCRBY", key(job_id), "duplicates", 1)
          end
          true
        else
          false
        end
      end
    end

    # ---- role-based ----
    def append_role(job_id:, email:)
      RedisPool.with do |r|
        r.pipelined do
          r.call("RPUSH", list_key(job_id, "role_list"),     email.to_s)
          r.call("RPUSH", list_key(job_id, "invalid_list"),  email.to_s)
          r.call("HINCRBY", key(job_id), "processed", 1)
          r.call("HINCRBY", key(job_id), "invalid",   1)
          r.call("HINCRBY", key(job_id), "role_rejected", 1)
        end
      end
    end

    # ---- regular result ----
    # result: { email:, domain:, valid_format:, mx_records:, disposable:, ... }
    def append(job_id:, result:)
      email   = result[:email].to_s
      domain  = result[:domain].to_s.downcase
      allowed = EmailValidatorService::ALLOWED_MAIL_DOMAINS.include?(domain)

      mx_ok = result[:mx_records]
      mx_ok = true if allowed && mx_ok.nil?
      is_valid = (!!result[:valid_format]) && allowed && !!mx_ok && !result[:disposable]

      RedisPool.with do |r|
        r.pipelined do
          # лічильники
          r.call("HINCRBY", key(job_id), "processed", 1)
          r.call("HINCRBY", key(job_id), (is_valid ? "valid" : "invalid"), 1)

          # відповідний LIST
          r.call("RPUSH", list_key(job_id, is_valid ? "valid_list" : "invalid_list"), email)

          # короткий «живий лог» — тримаємо останні RESULTS_TAIL
          r.call("LPUSH", list_key(job_id, "results_list"), JSON.generate(result.merge(valid: is_valid)))
          r.call("LTRIM", list_key(job_id, "results_list"), 0, RESULTS_TAIL - 1)
        end
      end
    end

    # ---- read light (для /emails/progress) ----
    # Повертаємо ТІЛЬКИ лічильники + короткий results_tail.
    # Великі списки не тягнемо (для них є chunk/download).
    def read(job_id)
      RedisPool.with do |r|
        h = Hash[*((r.call("HGETALL", key(job_id)) || []))]
        return nil if h.empty?

        counts = {
          "total"         => h["total"].to_i,
          "processed"     => h["processed"].to_i,
          "valid"         => h["valid"].to_i,
          "invalid"       => h["invalid"].to_i,
          "done"          => h["done"].to_i == 1,
          "role_rejected" => h["role_rejected"].to_i,
          "duplicates"    => h["duplicates"].to_i
        }

        raw = r.call("LRANGE", list_key(job_id, "results_list"), 0, RESULTS_TAIL - 1) || []
        results = raw.map { |s| safe_parse_json(s) }.compact

        counts.merge!(
          "results"         => results,
          "valid_list"      => [], # великі масиви НЕ повертаємо
          "invalid_list"    => [],
          "role_list"       => [],
          "duplicates_list" => []
        )
      end
    end

    # ---- chunk API для великих списків (role/duplicates/valid/invalid) ----
    def fetch_chunk(job_id:, kind:, offset:, limit:)
      lname =
        case kind
        when "role"       then "role_list"
        when "duplicates" then "duplicates_list"
        when "valid"      then "valid_list"
        when "invalid"    then "invalid_list"
        else
          return { items: [], next_offset: offset, eof: true }
        end

      start = offset
      stop  = offset + limit - 1

      RedisPool.with do |r|
        slice = r.call("LRANGE", list_key(job_id, lname), start, stop) || []
        llen  = r.call("LLEN",   list_key(job_id, lname)).to_i
        next_offset = offset + slice.length
        eof = next_offset >= llen
        { items: slice, next_offset: next_offset, eof: eof }
      end
    end

    # ---- для download ----
    def dump_list(job_id:, kind:)
      lname =
        case kind
        when "role"       then "role_list"
        when "duplicates" then "duplicates_list"
        when "valid"      then "valid_list"
        when "invalid"    then "invalid_list"
        else return []
        end

      RedisPool.with do |r|
        r.call("LRANGE", list_key(job_id, lname), 0, -1) || []
      end
    end

    private

    def safe_parse_json(s)
      JSON.parse(s)
    rescue
      nil
    end
  end
end
