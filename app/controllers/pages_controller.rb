# app/controllers/pages_controller.rb
class PagesController < ApplicationController
  def home
  end

  def upload
    file = params[:file]
    return render json: { success: false, error: 'Файл не обрано' } if file.nil?

    content = file.read.force_encoding('UTF-8')

    uuid = SecureRandom.uuid
    cache_key = "upload:#{uuid}"
    ok = Rails.cache.write(
      cache_key,
      {
        name: file.original_filename,
        type: file.content_type,
        size: file.size,
        content: content
      },
      expires_in: 30.minutes
    )
    return render json: { success: false, error: 'Не вдалося зберегти файл у кеш' } unless ok

    render json: { success: true, key: uuid }
  rescue => e
    render json: { success: false, error: e.message }
  end

  def process_file
    uuid = params[:key].presence
    unless uuid
      redirect_to root_path, alert: 'Ключ файлу не передано. Завантажте файл ще раз.' and return
    end

    data = Rails.cache.read("upload:#{uuid}")
    unless data
      redirect_to root_path, alert: 'Дані файлу недоступні або протухли. Завантажте файл ще раз.' and return
    end

    @file_data = { name: data[:name], type: data[:type], size: data[:size] }
    @emails    = parse_file_content(data[:content], data[:name])

    if @emails.empty?
      redirect_to root_path, alert: 'Не вдалося знайти email-адреси у файлі.' and return
    end

    @total         = @emails.size
    @processed     = 0
    @valid_count   = 0
    @invalid_count = 0
    @unknown_count = 0
    @results       = []

    render 'process'
  end

  private

  # ⚠️ ЖОДНОЇ "нормалізації" з обрізанням лапок!
  # Беремо сирі кандидати з сервісу, унікалізуємо та знижуємо лише домен.
  def parse_file_content(content, _filename)
    raw_items = ExtractEmailsService.call(content.to_s)

    seen = {}
    out  = []
    raw_items.each do |e|
      next if e.to_s.strip.empty?
      local, dom = e.split('@', 2)
      next if local.blank? || dom.blank?

      norm = "#{local}@#{dom.downcase}"  # локаль залишаємо як є (із лапкою теж)
      next if seen[norm]
      seen[norm] = true
      out << norm
    end

    out
  end
end
