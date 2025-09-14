# app/services/progress_store.rb
class ProgressStore
  PREFIX = "email_validation_job:"
  ALLOWED_MAIL_DOMAINS = EmailValidatorService::ALLOWED_MAIL_DOMAINS

  def self.key(job_id) = "#{PREFIX}#{job_id}"

  def self.init(job_id:, total:)
    Rails.cache.write(
      key(job_id),
      {
        "total" => total,
        "processed" => 0,
        "valid" => 0,
        "invalid" => 0,
        "done" => false,

        # коротка вітрина (для таблиці)
        "results" => [],

        # повні списки
        "valid_list" => [],
        "invalid_list" => [],

        # службові
        "role_rejected" => 0,
        "role_list"     => [],

        # дублікати
        "duplicates"      => 0,
        "duplicates_list" => [],

        # «бачені» емейли (щоб ловити дублікати під час перевірки)
        "seen" => {}
      },
      expires_in: 1.hour
    )
  end

  # === дублікати ===
  # Повертає true, якщо email уже бачили (і фіксує дублікат у статистиці),
  # інакше позначає як «бачений» та повертає false.
  def self.check_and_mark_seen(job_id:, email:)
    state = Rails.cache.read(key(job_id)) || {}
    seen  = state["seen"] || {}

    original = email.to_s
    norm_key = original.strip.downcase

    if seen[norm_key]
      dups = state["duplicates_list"] || []
      dups << original
      Rails.cache.write(
        key(job_id),
        state.merge(
          "processed"       => state["processed"].to_i + 1,
          "duplicates"      => state["duplicates"].to_i + 1,
          "duplicates_list" => dups
        ),
        expires_in: 1.hour
      )
      true
    else
      seen[norm_key] = true
      Rails.cache.write(
        key(job_id),
        state.merge("seen" => seen),
        expires_in: 1.hour
      )
      false
    end
  end

  # === службові ===
  def self.append_role(job_id:, email:)
    state         = Rails.cache.read(key(job_id)) || {}
    role_list     = state["role_list"]     || []
    invalid_list  = state["invalid_list"]  || []

    role_list    << email.to_s
    invalid_list << email.to_s

    Rails.cache.write(
      key(job_id),
      state.merge(
        "processed"     => state["processed"].to_i + 1,
        "invalid"       => state["invalid"].to_i + 1,
        "role_rejected" => state["role_rejected"].to_i + 1,
        "role_list"     => role_list,
        "invalid_list"  => invalid_list
      ),
      expires_in: 1.hour
    )
  end

  # === звичайний запис результату ===
  def self.append(job_id:, result:)
    state   = Rails.cache.read(key(job_id)) || {}
    email   = result[:email].to_s.strip
    domain  = result[:domain].to_s.downcase
    allowed = ALLOWED_MAIL_DOMAINS.include?(domain)

    mx_ok = result[:mx_records]
    mx_ok = true if allowed && mx_ok.nil?
    mx_ok = !!mx_ok

    is_valid = (!!result[:valid_format]) && allowed && mx_ok && !result[:disposable]

    processed = state["processed"].to_i + 1
    valid     = state["valid"].to_i   + (is_valid ? 1 : 0)
    invalid   = state["invalid"].to_i + (is_valid ? 0 : 1)

    results = (state["results"] || [])
    results.unshift(result.merge(valid: is_valid))
    results = results.first(200)

    vlist = state["valid_list"]   || []
    ilist = state["invalid_list"] || []
    (is_valid ? vlist : ilist) << email

    Rails.cache.write(
      key(job_id),
      state.merge(
        "processed"    => processed,
        "valid"        => valid,
        "invalid"      => invalid,
        "results"      => results,
        "valid_list"   => vlist,
        "invalid_list" => ilist
      ),
      expires_in: 1.hour
    )
  end

  def self.finish(job_id)
    state = Rails.cache.read(key(job_id)) || {}
    Rails.cache.write(key(job_id), state.merge("done" => true), expires_in: 1.hour)
  end

  def self.read(job_id)
    Rails.cache.read(key(job_id))
  end
end
