# app/services/progress_store.rb
class ProgressStore
  PREFIX = "email_validation_job:"

  ALLOWED_MAIL_DOMAINS = EmailValidatorService::ALLOWED_MAIL_DOMAINS

  def self.key(job_id) = "#{PREFIX}#{job_id}"

  def self.init(job_id:, total:)
    Rails.cache.write(
      key(job_id),
      {
        "total" => total, "processed" => 0,
        "valid" => 0, "invalid" => 0, "done" => false,
        "results" => [],
        "valid_list" => [],
        "invalid_list" => []
      },
      expires_in: 1.hour
    )
  end

  # result: { email:, valid_format:, domain:, disposable:, mx_records: }
  def self.append(job_id:, result:)
    state   = Rails.cache.read(key(job_id)) || {}
    email   = result[:email].to_s.strip
    domain  = result[:domain].to_s.downcase
    allowed = ALLOWED_MAIL_DOMAINS.include?(domain)

    # жорстке правило: приймаємо лише allowed-домени
    mx_ok = result[:mx_records]
    mx_ok = true if allowed && mx_ok.nil?
    mx_ok = !!mx_ok

    is_valid = (!!result[:valid_format]) && allowed && mx_ok && !result[:disposable]

    # агрегати
    processed = state["processed"].to_i + 1
    valid     = state["valid"].to_i   + (is_valid ? 1 : 0)
    invalid   = state["invalid"].to_i + (is_valid ? 0 : 1)

    # коротка вітрина (для таблиці) — останні 200
    results = (state["results"] || [])
    results.unshift(result.merge(valid: is_valid))
    results = results.first(200)

    # повні списки
    vlist = state["valid_list"]   || []
    ilist = state["invalid_list"] || []
    if is_valid
      vlist << email
    else
      ilist << email
    end

    Rails.cache.write(
      key(job_id),
      state.merge(
        "processed" => processed,
        "valid"     => valid,
        "invalid"   => invalid,
        "results"   => results,
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
