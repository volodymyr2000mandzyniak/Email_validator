# app/jobs/email_validation_job.rb
# frozen_string_literal: true

class EmailValidationJob < ApplicationJob
  queue_as :default

  BATCH_SIZE   = 500   # читаємо по 500 для логіки
  FLUSH_EVERY = 200   # у кеш пишемо раз на 200 (приблизно)

  def perform(job_id:, emails:)
    emails = Array(emails)

    # локальний дедуп в межах одного запуску (нормалізуємо тільки для ключа порівняння)
    seen = {}

    # робочі буфери, що флашаться в ProgressStore
    batch = new_batch

    emails.each_slice(BATCH_SIZE) do |chunk|
      chunk.each do |email|
        original = email.to_s
        norm_key = original.strip.downcase
        if seen[norm_key]
          batch[:processed]      += 1
          batch[:duplicates]     += 1
          batch[:duplicates_list] << original
          flush_if_needed(job_id, batch)
          next
        end
        seen[norm_key] = true

        # 1) службові адреси
        verdict = RoleAddressFilter.role_like?(original)
        if verdict[:role_based]
          batch[:processed]      += 1
          batch[:invalid]        += 1
          batch[:role_rejected]  += 1
          batch[:role_list]      << original
          batch[:invalid_list]   << original
          flush_if_needed(job_id, batch)
          next
        end

        # 2) звичайна перевірка формату/домену
        result = EmailValidatorService.validate_one(original)
        ok = ProgressStore.result_ok?(result)

        batch[:processed] += 1
        if ok
          batch[:valid]      += 1
          batch[:valid_list] << original
        else
          batch[:invalid]      += 1
          batch[:invalid_list] << original
        end

        # у «вітрину» результатів (тільки останні RESULTS_LIMIT — ProgressStore підріже)
        batch[:results] << result.merge(valid: ok)

        flush_if_needed(job_id, batch)
      end

      # флашимо кінець чанку
      ProgressStore.apply_batch!(job_id: job_id, batch: batch) if batch_changed?(batch)
      batch = new_batch
    end

    # фінальний флаш (якщо щось лишилось)
    ProgressStore.apply_batch!(job_id: job_id, batch: batch) if batch_changed?(batch)

    ProgressStore.finish(job_id)
  end

  private

  def new_batch
    {
      processed: 0, valid: 0, invalid: 0,
      role_rejected: 0, duplicates: 0,
      results: [],
      valid_list: [], invalid_list: [],
      role_list: [], duplicates_list: []
    }
  end

  def batch_changed?(batch)
    batch[:processed] > 0 ||
      batch[:results].any? ||
      batch[:valid_list].any? || batch[:invalid_list].any? ||
      batch[:role_list].any? || batch[:duplicates_list].any?
  end

  def flush_if_needed(job_id, batch)
    # Пишемо не частіше ніж раз на FLUSH_EVERY опрацьованих записів
    if batch[:processed] % FLUSH_EVERY == 0
      ProgressStore.apply_batch!(job_id: job_id, batch: batch)
      batch.replace(new_batch)
    end
  end
end
