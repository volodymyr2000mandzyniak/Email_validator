# frozen_string_literal: true

# НІЧОГО не чіпаємо всередині класу. Просто прогріємо конфіг,
# щоб у dev/console помилки YAML ловились раніше.
Rails.application.config.to_prepare do
  begin
    RoleAddressFilter.send(:local_parts_set)
    RoleAddressFilter.send(:compiled_patterns)
  rescue => e
    Rails.logger.warn("[RoleAddressFilter initializer] #{e.class}: #{e.message}")
  end
end
