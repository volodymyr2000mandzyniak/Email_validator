# app/jobs/email_validation_job.rb
# frozen_string_literal: true

class EmailValidationJob < ApplicationJob
  queue_as :default
  BATCH_SIZE = 100

  def perform(job_id:, emails:)
    emails = Array(emails)

    emails.each_slice(BATCH_SIZE) do |chunk|
      chunk.each do |email|
        # 0) дублікати — рахуємо і пропускаємо все інше
        next if ProgressStore.check_and_mark_seen(job_id: job_id, email: email)

        # 1) службові
        verdict = RoleAddressFilter.role_like?(email)
        if verdict[:role_based]
          ProgressStore.append_role(job_id: job_id, email: email)
          next
        end

        # 2) формат/домен
        result = EmailValidatorService.validate_one(email)
        ProgressStore.append(job_id: job_id, result: result)
      end
    end

    ProgressStore.finish(job_id)
  end
end
