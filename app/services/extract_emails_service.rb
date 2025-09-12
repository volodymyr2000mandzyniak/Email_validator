# app/services/extract_emails_service.rb
# frozen_string_literal: true

class ExtractEmailsService
  # Ліберальне витягнення local@domain усередині рядка (без лапок у середині токена)
  RAW_EMAIL_RE = /
    [^\s<>"'()\[\],;:]+
    @
    [^\s<>"'()\[\],;:]+
  /ix

  MAX_ITEMS = 50_000

  class << self
    def call(content)
      text = content.to_s

      # 1) Токени "всередині" тексту
      tokens = text.scan(RAW_EMAIL_RE)

      # 2) ЦІЛІ РЯДКИ з @ — зберігаємо краєві символи (", ., тощо),
      # щоб проблемні локалі не "очистились".
      per_line = text.each_line.map { |ln| ln.to_s.strip }.select { |ln| ln.include?('@') }

      # Об’єднати, стабільно унікалізувати, обрізати розмір
      merged = stable_uniq(tokens + per_line).first(MAX_ITEMS)
      merged
    end

    private

    def stable_uniq(arr)
      seen = {}
      arr.each_with_object([]) do |e, out|
        next if e.blank? || seen[e]
        seen[e] = true
        out << e
      end
    end
  end
end
