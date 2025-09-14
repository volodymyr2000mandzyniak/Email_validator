# app/services/progress_store.rb
class ProgressStore
  PREFIX = "email_validation_job:"

  # Скільки елементів тримати "у витрині" в кеші (для UI). Повні списки додамо пізніше окремо.
  RESULTS_LIMIT       = 200       # останні результати для таблиці/логів
  LIST_SAMPLE_LIMIT   = 5_000     # максимум email-ів у valid_list/invalid_list/role_list/duplicates_list (для UI)

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

        # коротка вітрина (для таблиці/логів)
        "results" => [],

        # повні списки для UI (обмежені)
        "valid_list"      => [],
        "invalid_list"    => [],
        "role_list"       => [],
        "duplicates_list" => [],

        # лічильники для окремих категорій
        "role_rejected" => 0,
        "duplicates"    => 0
      },
      expires_in: 1.hour
    )
  end

  # === НОВЕ: пакетне застосування змін ===
  # batch = {
  #   processed: Integer,
  #   valid: Integer,
  #   invalid: Integer,
  #   role_rejected: Integer,
  #   duplicates: Integer,
  #   results: [hash, ...],            # (до 200 останніх)
  #   valid_list: [email, ...],
  #   invalid_list: [email, ...],
  #   role_list: [email, ...],
  #   duplicates_list: [email, ...]
  # }
  def self.apply_batch!(job_id:, batch:)
    state = Rails.cache.read(key(job_id)) || {}

    # лічильники
    processed = state["processed"].to_i + (batch[:processed] || 0)
    valid     = state["valid"].to_i     + (batch[:valid] || 0)
    invalid   = state["invalid"].to_i   + (batch[:invalid] || 0)
    role_rej  = state["role_rejected"].to_i + (batch[:role_rejected] || 0)
    dups_cnt  = state["duplicates"].to_i    + (batch[:duplicates] || 0)

    # результати (обмежуємо RESULTS_LIMIT)
    results = (Array(state["results"]) + Array(batch[:results])).last(RESULTS_LIMIT)

    # списки для UI (обмежуємо LIST_SAMPLE_LIMIT)
    valid_list      = (Array(state["valid_list"])      + Array(batch[:valid_list])).last(LIST_SAMPLE_LIMIT)
    invalid_list    = (Array(state["invalid_list"])    + Array(batch[:invalid_list])).last(LIST_SAMPLE_LIMIT)
    role_list       = (Array(state["role_list"])       + Array(batch[:role_list])).last(LIST_SAMPLE_LIMIT)
    duplicates_list = (Array(state["duplicates_list"]) + Array(batch[:duplicates_list])).last(LIST_SAMPLE_LIMIT)

    Rails.cache.write(
      key(job_id),
      state.merge(
        "processed"        => processed,
        "valid"            => valid,
        "invalid"          => invalid,
        "results"          => results,
        "valid_list"       => valid_list,
        "invalid_list"     => invalid_list,
        "role_rejected"    => role_rej,
        "role_list"        => role_list,
        "duplicates"       => dups_cnt,
        "duplicates_list"  => duplicates_list
      ),
      expires_in: 1.hour
    )
  end

  # Сумісність: якщо десь ще викликається старий append (залишаємо, але він не використовується в новій джобі)
  def self.append(job_id:, result:)
    apply_batch!(
      job_id: job_id,
      batch: {
        processed: 1,
        valid: (result_ok?(result) ? 1 : 0),
        invalid: (result_ok?(result) ? 0 : 1),
        results: [result.merge(valid: result_ok?(result))],
        (result_ok?(result) ? :valid_list : :invalid_list) => [result[:email].to_s]
      }
    )
  end

  def self.append_role(job_id:, email:)
    apply_batch!(
      job_id: job_id,
      batch: {
        processed: 1,
        invalid: 1,
        role_rejected: 1,
        role_list: [email.to_s],
        invalid_list: [email.to_s]
      }
    )
  end

  def self.append_duplicate(job_id:, email:)
    apply_batch!(
      job_id: job_id,
      batch: {
        processed: 1,
        duplicates: 1,
        duplicates_list: [email.to_s]
      }
    )
  end

  def self.finish(job_id)
    state = Rails.cache.read(key(job_id)) || {}
    Rails.cache.write(key(job_id), state.merge("done" => true), expires_in: 1.hour)
  end

  def self.read(job_id)
    Rails.cache.read(key(job_id))
  end

  # ---- helpers ----
  def self.result_ok?(result)
    email   = result[:email].to_s.strip
    domain  = result[:domain].to_s.downcase
    allowed = ALLOWED_MAIL_DOMAINS.include?(domain)

    mx_ok = result[:mx_records]
    mx_ok = true if allowed && mx_ok.nil?
    mx_ok = !!mx_ok

    (!!result[:valid_format]) && allowed && mx_ok && !result[:disposable]
  end
end
