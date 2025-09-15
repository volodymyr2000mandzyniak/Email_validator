# frozen_string_literal: true
class PagesController < ApplicationController
  def home; end

  def upload
    file = params[:file]
    return render json: { success: false, error: 'Файл не обрано' } if file.nil?

    key = SecureRandom.uuid
    dir = Rails.root.join("storage", "uploads", key)
    FileUtils.mkdir_p(dir)
    dst = dir.join(file.original_filename)

    File.open(dst, "wb") { |io| IO.copy_stream(file.tempfile, io) }

    UploadSession.create!(
      key: key,
      filename: file.original_filename,
      content_type: file.content_type,
      byte_size: file.size,
      path: dst.to_s
    )

    render json: { success: true, key: key }
  rescue => e
    render json: { success: false, error: e.message }
  end

  def process_file
    uuid = params[:key].presence
    unless uuid
      redirect_to root_path, alert: 'Ключ файлу не передано. Завантажте файл ще раз.' and return
    end

    @upload = UploadSession.find_by(key: uuid)
    unless @upload&.path && File.exist?(@upload.path)
      redirect_to root_path, alert: 'Файл не знайдено (шлях недоступний). Завантажте файл ще раз.' and return
    end

    @file_data = { name: @upload.filename, type: @upload.content_type, size: @upload.byte_size }

    # Початкові нулі — реальні значення підтягнуться із прогресу
    @total         = 0
    @processed     = 0
    @valid_count   = 0
    @invalid_count = 0
    @unknown_count = 0
    @results       = []

    # Передаємо ключ на фронт
    @job_key = uuid

    render 'process'
  end
end
