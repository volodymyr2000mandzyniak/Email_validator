# app/services/email_validator_service.rb
# frozen_string_literal: true

require "timeout"
require "resolv"  # для NORMAL-режиму MX-lookup

class EmailValidatorService
  # Вкл/викл швидкий режим (без DNS/MX). За замовчуванням — швидко.
  FAST = ENV.fetch("FAST_VALIDATE", "1") == "1"

  # Кеш MX/Disposable у NORMAL-режимі
  MX_CACHE_TTL         = 12.hours
  DISPOSABLE_CACHE_TTL = 12.hours
  MX_TIMEOUT_SEC       = (ENV["MX_TIMEOUT_SEC"] || "0.25").to_f # 250ms за замовчуванням

  # ✅ Whitelist надійних поштових провайдерів
  ALLOWED_MAIL_DOMAINS = %w[
    gmail.com yahoo.com outlook.com hotmail.com live.com icloud.com
    yandex.ru yandex.com ukr.net i.ua meta.ua proton.me protonmail.com zoho.com
  ].freeze

  # ===== Правила формату (практичні) =====
  LOCAL_RE  = /\A[a-z0-9](?:[a-z0-9._+\-]*[a-z0-9])?\z/i
  LABEL_RE  = /\A[a-z0-9](?:[a-z0-9\-]*[a-z0-9])?\z/i
  DOMAIN_RE = /\A(?:[a-z0-9](?:[a-z0-9\-]*[a-z0-9])?\.)+[a-z]{2,}\z/i

  class << self
    # Пакетна перевірка
    def validate(emails)
      # Простий map — IO тут немає, вся «важкість» усередині validate_one
      emails.map { |email| validate_one(email) }
    end

    # Перевірка однієї адреси → { email, valid_format, domain, disposable, mx_records }
    def validate_one(email)
      raw = email.to_s.strip
      result = { email: raw }

      begin
        # ШВИДКИЙ парсинг без додаткових алокацій/гемів
        at = raw.index("@")
        if at.nil? || at.zero? || at == raw.length - 1
          result[:valid_format] = false
          result[:domain]       = nil
          result[:disposable]   = false
          result[:mx_records]   = false
          return result
        end

        local  = raw[0...at]
        domain = raw[(at + 1)..].to_s.downcase

        # Суворий формат
        vf = strict_format_ok?(local, domain)
        result[:valid_format] = vf
        result[:domain]       = domain.presence
        return fast_fail(result) unless vf

        allowed = ALLOWED_MAIL_DOMAINS.include?(domain)

        # Disposable (кешуємо; для FAST також можемо перевіряти, бо це локальний Hash/DB/файл у гемі)
        result[:disposable] =
          if defined?(DisposableMail) && DisposableMail.respond_to?(:disposable?)
            if FAST
              !!DisposableMail.disposable?(domain)
            else
              Rails.cache.fetch("disposable:#{domain}", expires_in: DISPOSABLE_CACHE_TTL) do
                !!DisposableMail.disposable?(domain)
              end
            end
          else
            false
          end

        # MX:
        # FAST → не перевіряємо (nil для allowed, false для інших)
        # NORMAL → MX з таймаутом + кеш
        result[:mx_records] =
          if FAST
            allowed ? nil : false
          else
            if allowed
              # для allowed доменів MX пропускаємо (з міркувань продуктивності), це ок для ProgressStore
              nil
            else
              Rails.cache.fetch("mx:#{domain}", expires_in: MX_CACHE_TTL) do
                mx_lookup(domain)
              end
            end
          end

      rescue => e
        Rails.logger.warn("[EmailValidatorService] error for #{email}: #{e.class} #{e.message}")
        return fast_fail(result)
      end

      result
    end

    private

    # Суворі правила формату (без EmailAddress gem)
    def strict_format_ok?(local, domain)
      return false if local.blank? || domain.blank?

      # локальна: без лапок/апострофів, без крапок на краях, без двох крапок
      return false if local.include?('"') || local.include?("'")
      return false if local.start_with?('.') || local.end_with?('.') || local.include?('..')
      return false unless LOCAL_RE.match?(local)

      # домен: без подвійних крапок, валідний шаблон
      return false if domain.include?('..')
      return false unless DOMAIN_RE.match?(domain)

      # окремі labels
      labels = domain.split('.')
      return false if labels.any? { |lbl| lbl.length > 63 || !LABEL_RE.match?(lbl) }

      true
    end

    # Fallback на помилку
    def fast_fail(result)
      result[:valid_format] = false
      result[:domain]       = nil
      result[:disposable]   = false
      result[:mx_records]   = false
      result
    end

    # MX-lookup з коротким таймаутом; повертає true/false
    def mx_lookup(domain)
      Timeout.timeout(MX_TIMEOUT_SEC) do
        Resolv::DNS.open do |dns|
          ress = dns.getresources(domain, Resolv::DNS::Resource::IN::MX)
          # якщо MX немає — можна ще спробувати A (деякі приймають пошту на A), але лишимо простіше
          !ress.empty?
        end
      end
    rescue Timeout::Error, Resolv::ResolvError, StandardError
      false
    end
  end
end
