# frozen_string_literal: true
require 'set'

class RoleAddressFilter
  class << self
    # => { role_based: true/false, reason: "..." }
    def role_like?(email)
      raw = email.to_s.strip
      return fail_result('blank') if raw.empty?
      return fail_result('no-at') unless raw.include?('@')

      local, domain = raw.split('@', 2)
      return fail_result('bad-split') if local.blank? || domain.blank?

      local_down = local.to_s.downcase

      # 0) прибираємо лапки по краях (якщо хтось вставив "user")
      local_core = local_down.gsub(/\A["']+/, '').gsub(/["']+\z/, '')

      # 1) швидкі перевірки: exact match у словнику
      return ok_result("exact: #{local_core}") if local_parts_set.include?(local_core)

      # 2) токени по . _ - + : як тільки є ХОЧ ОДИН токен-роль — це службова адреса
      tokens = local_core.split(/[._+\-]+/).reject(&:blank?)
      unless tokens.empty?
        if tokens.any? { |t| local_parts_set.include?(t) }
          return ok_result("token: #{(tokens & local_parts_set.to_a).join(',')}")
        end
      end

      # 3) починається з role-слова і далі кінець або розділювач
      if starts_with_role?(local_core)
        return ok_result('starts-with-role')
      end

      # 4) регулярки з YAML (перевіряємо по "сирій" локалі без дот-нормалізації)
      compiled_patterns.each do |re|
        return ok_result("pattern: #{re.source}") if local_core.match?(re)
      end

      fail_result('no-match')
    end

    # Масовий фільтр (опційний)
    def filter(emails)
      kept, rejected, details = [], [], []
      emails.each do |e|
        v = role_like?(e)
        (v[:role_based] ? rejected : kept) << e
        details << { email: e, role_based: v[:role_based], reason: v[:reason] }
      end
      { kept:, rejected:, details: }
    end

    private

    def ok_result(reason)   = { role_based: true,  reason: reason }
    def fail_result(reason) = { role_based: false, reason: reason }

    def starts_with_role?(local_core)
      role_words = local_parts_set.to_a.map { |w| Regexp.escape(w) }
      return false if role_words.empty?

      re = /\A(?:#{role_words.join('|')})(?:$|[._+\-])/i
      local_core.match?(re)
    end

    # ---- доступ до конфігу ----
    def cfg
      @cfg ||= begin
        (Rails.application.config_for(:role_addresses) || {}).with_indifferent_access
      rescue
        {}.with_indifferent_access
      end
    end

    def local_parts_set
      @local_parts_set ||= cfg.fetch(:local_parts, []).map(&:to_s).map(&:downcase).to_set
    end

    def compiled_patterns
      @compiled_patterns ||= cfg.fetch(:patterns, []).map { |s| Regexp.new(s.to_s, Regexp::IGNORECASE) }
    end
  end
end
