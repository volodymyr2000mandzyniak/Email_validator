# app/controllers/emails_controller.rb
class EmailsController < ApplicationController
  protect_from_forgery with: :null_session, only: [:bulk_validate]

  def bulk_validate
    emails = params[:emails].is_a?(Array) ? params[:emails] : []
    return render json: { success: false, error: "Порожній список email’ів" } if emails.empty?

    job_id = SecureRandom.uuid
    ProgressStore.init(job_id: job_id, total: emails.size)
    EmailValidationJob.perform_later(job_id: job_id, emails: emails)

    render json: { success: true, job_id: job_id }
  end

  def progress
    job_id = params[:job_id].to_s
    state = ProgressStore.read(job_id)
    return render json: { success: false, error: "Невідомий job_id" } if state.nil?

    duplicates_val = state["duplicates"].to_i

    render json: {
      success: true,
      total:        state["total"].to_i,
      processed:    state["processed"].to_i,
      valid:        state["valid"].to_i,
      invalid:      state["invalid"].to_i,
      done:         !!state["done"],
      results:      state["results"] || [],
      valid_list:   state["valid_list"] || [],
      invalid_list: state["invalid_list"] || [],

      role_rejected:   state["role_rejected"].to_i,
      role_list:       state["role_list"] || [],

      # основне поле
      duplicates:        duplicates_val,
      duplicates_list:   state["duplicates_list"] || [],

      # аліас для зворотної сумісності з фронтом
      duplicate_count:   duplicates_val
    }
  end
end
