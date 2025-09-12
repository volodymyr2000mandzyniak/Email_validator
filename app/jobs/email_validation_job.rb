# app/jobs/email_validation_job.rb
class EmailValidationJob < ApplicationJob
  queue_as :default

  def perform(job_id:, emails:)
    emails.each do |email|
      begin
        result = EmailValidatorService.validate([email]).first || {}
      rescue => _
        # якщо сервіс кинув, зафіксуємо як невалідний формат
        result = { email: email, valid_format: false, domain: nil, disposable: false, mx_records: false }
      end

      ProgressStore.append(job_id: job_id, result: symbolize_keys(result))
    end

    ProgressStore.finish(job_id)
  end

  private

  def symbolize_keys(h)
    h.transform_keys { |k| k.is_a?(String) ? k.to_sym : k }
  end
end
