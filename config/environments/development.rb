require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.enable_reloading = true
  config.eager_load = false

  # Show full error reports.
  config.consider_all_requests_local = true

  # Enable server timing.
  config.server_timing = true

  # Enable/disable Action Controller caching. By default Action Controller caching is disabled.
  # Run rails dev:cache to toggle Action Controller caching.
  if Rails.root.join("tmp/caching-dev.txt").exist?
    config.action_controller.perform_caching = true
    config.action_controller.enable_fragment_cache_logging = true
    config.public_file_server.headers = { "cache-control" => "public, max-age=#{2.days.to_i}" }
  else
    config.action_controller.perform_caching = false
  end

  # Change to :null_store to avoid any caching.
  config.cache_store = :memory_store

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Don't care if the mailer can't send.
  config.action_mailer.raise_delivery_errors = false

  # Make template changes take effect immediately.
  config.action_mailer.perform_caching = false

  # Set localhost to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = { host: "localhost", port: 3000 }

  # Print deprecation notices to the Rails logger.
  config.active_support.deprecation = :log

  # Raise an error on page load if there are pending migrations.
  config.active_record.migration_error = :page_load

  # Highlight code that triggered database queries in logs.
  config.active_record.verbose_query_logs = true

  # Append comments with runtime information tags to SQL queries in logs.
  config.active_record.query_log_tags_enabled = true

  # Highlight code that enqueued background job in logs.
  config.active_job.verbose_enqueue_logs = true


  config.action_view.annotate_rendered_view_with_filenames = true

  config.action_controller.raise_on_missing_callback_actions = true

  config.cache_store = :memory_store, { size: 128.megabytes }
  config.action_controller.perform_caching = true

  # config/environments/development.rb
  config.action_controller.perform_caching = true
  config.cache_store = :redis_cache_store, {
    url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1"),
    namespace: "email_validator:cache",
    compress: true,
    compress_threshold: 4.kilobytes
  }
  config.action_controller.enable_fragment_cache_logging = true
end
