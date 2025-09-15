# frozen_string_literal: true
class EmailValidationJob < ApplicationJob
  queue_as :default
  BATCH_SIZE = 1_000

  # Працює або з emails:, або з file_path:
  def perform(job_id:, emails: nil, file_path: nil)
    if file_path.present?
      process_stream(job_id: job_id, file_path: file_path)
    else
      process_array(job_id: job_id, emails: Array(emails))
    end
    ProgressStore.finish(job_id)
  end

  private

  def process_array(job_id:, emails:)
    emails.each_slice(BATCH_SIZE) do |chunk|
      chunk.each { |email| handle_one(job_id, email) }
    end
  end

  def process_stream(job_id:, file_path:)
    ExtractEmailsStreamService.call(file_path) do |email|
      handle_one(job_id, email)
    end
  end

  def handle_one(job_id, email)
    # 0) дублікати
    return if ProgressStore.check_and_mark_seen(job_id: job_id, email: email)

    # 1) службові
    verdict = RoleAddressFilter.role_like?(email)
    if verdict[:role_based]
      ProgressStore.append_role(job_id: job_id, email: email)
      return
    end

    # 2) формат/домен
    result = EmailValidatorService.validate_one(email)
    ProgressStore.append(job_id: job_id, result: result)
  end
end
