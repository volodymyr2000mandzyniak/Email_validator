class PagesController < ApplicationController
  def home
    # Головна сторінка
  end

  def upload
    begin
      file = params[:file]
      
      if file.nil?
        return render json: { success: false, error: 'Файл не обрано' }
      end

      # Зберігаємо файл в тимчасову сесію
      session[:uploaded_file] = {
        name: file.original_filename,
        type: file.content_type,
        size: file.size,
        content: file.read.force_encoding('UTF-8')
      }

      render json: { success: true, filename: file.original_filename }
    rescue => e
      render json: { success: false, error: e.message }
    end
  end

  def process_file
    @file_data = session[:uploaded_file]
    
    if @file_data.nil?
      redirect_to root_path, alert: 'Файл не знайдено. Будь ласка, завантажте файл знову.'
      return
    end

    # Парсимо файл залежно від типу
    @emails = parse_file_content(@file_data[:content], @file_data[:name])
    
    if @emails.empty?
      redirect_to root_path, alert: 'Не вдалося знайти email-адреси у файлі.'
      return
    end

    # Показуємо сторінку з знайденими email-адресами
    render 'process'
  end

  private

  def parse_file_content(content, filename)
    emails = []
    
    case File.extname(filename).downcase
    when '.txt'
      emails = content.scan(/\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i)
    when '.csv'
      # Простий парсинг CSV
      content.split("\n").each do |line|
        # Шукаємо email у кожному рядку
        emails.concat(line.scan(/\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i))
      end
    when '.json'
      begin
        data = JSON.parse(content)
        # Спроба знайти emails у JSON
        emails = find_emails_in_json(data)
      rescue JSON::ParserError
        # Якщо не JSON, шукаємо emails як у тексті
        emails = content.scan(/\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i)
      end
    else
      # Для інших типів файлів
      emails = content.scan(/\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i)
    end

    emails.uniq
  end

  def find_emails_in_json(data)
    emails = []
    
    case data
    when Array
      data.each { |item| emails.concat(find_emails_in_json(item)) }
    when Hash
      data.each do |key, value|
        if value.is_a?(String) && value.include?('@')
          emails.concat(value.scan(/\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i))
        else
          emails.concat(find_emails_in_json(value))
        end
      end
    when String
      emails.concat(data.scan(/\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i))
    end
    
    emails.uniq
  end
end