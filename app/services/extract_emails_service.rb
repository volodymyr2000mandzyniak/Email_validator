# app/services/extract_emails_service.rb
# frozen_string_literal: true

class ExtractEmailsService
  # Дуже ліберальний шаблон: просто "щось@щось" без пробілів і типових розділювачів
  LOOSE_EMAIL_RE = /
    [^\s<>"'()\[\]\\,;:]+   # локальна частина (ліберально)
    @
    [^\s<>"'()\[\]\\,;:]+   # доменна частина (може бути й без крапки)
  /x

  MAX_ITEMS = 200_000 # запобіжник на випадок дуже великих файлів

  class << self
    # Повертає ВСІ збіги у порядку появи, з дублікатами.
    # Абсолютно НІЧОГО не нормалізуємо і не унікалізуємо.
    def call(content)
      text = content.to_s

      # 1) Просто витягуємо всі токени, схожі на email (за ліберальним regex)
      tokens = text.scan(LOOSE_EMAIL_RE)

      # 2) ЖОДНОГО uniq! ЖОДНОЇ нормалізації! Лише обрізаємо за MAX_ITEMS, щоб не "вибухнути".
      tokens.first(MAX_ITEMS)
    end
  end
end
