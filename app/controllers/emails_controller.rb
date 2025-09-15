# frozen_string_literal: true
class EmailsController < ApplicationController
  protect_from_forgery with: :null_session, only: [:bulk_validate]

  # POST /emails/bulk_validate
  # Режими:
  #   { key: "<upload_session_key>" } — стрім із файлу (рекомендовано)
  #   { emails: [...] }               — старий режим (масив у пам'яті)
  def bulk_validate
    key    = params[:key].presence || params[:upload_key].presence || params[:job_key].presence
    emails = if params[:emails].is_a?(Array)
               params[:emails]
             elsif params.dig(:email, :emails).is_a?(Array)
               params.dig(:email, :emails)
             end

    if key.blank? && (emails.nil? || emails.empty?)
      return render json: { success: false, error: "Немає ні key, ні emails" }
    end

    job_id = SecureRandom.uuid

    if key.present?
      us = UploadSession.find_by(key: key)
      unless us && File.exist?(us.path)
        return render json: { success: false, error: "Файл не знайдено" }
      end
      ProgressStore.init(job_id: job_id, total: 0) # total невідомий наперед
      EmailValidationJob.perform_later(job_id: job_id, file_path: us.path)
    else
      ProgressStore.init(job_id: job_id, total: emails.size)
      EmailValidationJob.perform_later(job_id: job_id, emails: emails)
    end

    render json: { success: true, job_id: job_id }
  end

  # GET /emails/progress?job_id=...
  def progress
    job_id = params[:job_id].to_s
    state  = ProgressStore.read(job_id)
    return render json: { success: false, error: "Невідомий job_id" } if state.nil?

    render json: {
      success: true,
      total:           state["total"].to_i,
      processed:       state["processed"].to_i,
      valid:           state["valid"].to_i,
      invalid:         state["invalid"].to_i,
      done:            !!state["done"],
      results:         state["results"] || [],
      valid_list:      state["valid_list"] || [],
      invalid_list:    state["invalid_list"] || [],
      role_rejected:   state["role_rejected"].to_i,
      role_list:       state["role_list"] || [],
      duplicates:      state["duplicates"].to_i,
      duplicates_list: state["duplicates_list"] || []
    }
  end

  # GET /emails/chunk?job_id=...&kind=role|duplicates|valid|invalid&offset=0&limit=500
  def chunk
    job_id = params[:job_id].to_s
    kind   = params[:kind].to_s
    offset = params[:offset].to_i
    limit  = [[params[:limit].to_i, 1000].reject(&:zero?).first || 500, 5000].min
  
    # просто попросимо ProgressStore дати зріз із LIST
    data = ProgressStore.fetch_chunk(job_id: job_id, kind: kind, offset: offset, limit: limit)
    render json: { success: true, items: data[:items], next_offset: data[:next_offset], eof: data[:eof] }
  end


  # GET /emails/download?job_id=...&kind=role|duplicates|valid|invalid
  def download
    job_id = params[:job_id].to_s
    kind   = params[:kind].to_s
  
    items = ProgressStore.dump_list(job_id: job_id, kind: kind)
    return render plain: "bad kind", status: :bad_request if items.nil?
  
    filename_base =
      case kind
      when "role"       then "role_emails"
      when "duplicates" then "duplicates_emails"
      when "valid"      then "valid_emails"
      when "invalid"    then "invalid_emails"
      end
  
    send_data items.join("\n"),
              filename: "#{filename_base}_#{Time.now.strftime('%Y%m%d_%H%M%S')}.txt",
              type: "text/plain"
  end

end
