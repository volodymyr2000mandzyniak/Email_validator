# app/services/email_validator_service.rb
# frozen_string_literal: true

class EmailValidatorService
  # ✅ Whitelist для «великих»/надійних провайдерів (можеш розширювати)
  ALLOWED_MAIL_DOMAINS = %w[
    gmail.com yahoo.com outlook.com hotmail.com live.com icloud.com
    yandex.ru yandex.com ukr.net i.ua meta.ua proton.me protonmail.com zoho.com
  ].freeze

  # ===== Правила формату (практичні, «як у великих») =====
  #
  # Локальна частина:
  #  - перший символ: літера/цифра
  #  - далі: літери/цифри/._+- (без лапок/апострофів/пробілів)
  #  - заборонені: початкова/кінцева крапка, подвійні крапки
  LOCAL_RE  = /\A[a-z0-9](?:[a-z0-9._+\-]*[a-z0-9])?\z/i

  # Домен: labels з [a-z0-9-], між ними крапки, без дефіса на краях,
  # TLD >= 2 символів, без подвійних крапок
  LABEL_RE  = /\A[a-z0-9](?:[a-z0-9\-]*[a-z0-9])?\z/i
  DOMAIN_RE = /\A(?:[a-z0-9](?:[a-z0-9\-]*[a-z0-9])?\.)+[a-z]{2,}\z/i

  class << self
    # Пакетна перевірка (масив у → масив результатів)
    def validate(emails)
      emails.map { |email| validate_one(email) }
    end

    # Перевірка однієї адреси → { email, valid_format, domain, disposable, mx_records }
    def validate_one(email)
      result = { email: email }

      begin
        raw   = email.to_s.strip
        addr  = EmailAddress.new(raw)

        # Витягаємо частини як є, але страхуємось від nil
        local = addr.respond_to?(:local) ? addr.local.to_s : raw.split('@', 2).first.to_s
        host  = addr.respond_to?(:host)  ? addr.host.to_s  : raw.split('@', 2).last.to_s
        domain = host.downcase

        # Суворий формат (локал + домен) + базова валідація бібліотеки
        result[:valid_format] = strict_format_ok?(local, domain) && addr.valid?
        result[:domain]       = domain.presence

        allowed = ALLOWED_MAIL_DOMAINS.include?(domain)

        # Disposable перевіряємо ЛИШЕ для дозволених доменів (щоб не витрачати час)
        result[:disposable] =
          allowed && defined?(DisposableMail) && DisposableMail.respond_to?(:disposable?) ?
            !!DisposableMail.disposable?(domain) : false

        # Швидкий режим: для allowed доменів MX не викликаємо (nil = «не перевіряли»).
        # Для решти теж не робимо DNS (щоб не гальмувати) — ставимо false,
        # бо все одно такі домени «відсікаємо» у ProgressStore за правилом allowed-only.
        result[:mx_records] = allowed ? nil : false
      rescue => e
        Rails.logger.warn("[EmailValidatorService] error for #{email}: #{e.class} #{e.message}")
        result[:valid_format] = false
        result[:domain]       = nil
        result[:disposable]   = false
        result[:mx_records]   = false
      end

      result
    end

    private

    # Суворі правила формату (практично-корисні для реальних розсилок)
    def strict_format_ok?(local, domain)
      return false if local.blank? || domain.blank?

      # локальна частина: швидкі відсікання
      return false if local.include?('"') || local.include?("'") # лапки/апострофи — ні
      return false if local.start_with?('.') || local.end_with?('.') || local.include?('..')
      return false unless LOCAL_RE.match?(local)

      # домен: без подвійних крапок, з коректними labels і TLD >= 2
      return false if domain.include?('..')
      return false unless DOMAIN_RE.match?(domain)

      # додатково перевіримо кожну мітку, щоб не було дефіса на краях
      labels = domain.split('.')
      return false if labels.any? { |lbl| lbl.length > 63 || !LABEL_RE.match?(lbl) }

      true
    end
  end
end
