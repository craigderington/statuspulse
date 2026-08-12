require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  # Host Apache2 terminates TLS and forwards X-Forwarded-Proto: https. Without this,
  # Rails believes requests are http and ActionCable rejects the WebSocket handshake
  # because the Origin (https://statuspulse.org) fails its same-origin check.
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Skip http-to-https redirect for the default health check endpoint, so the container
  # healthcheck and Apache's probe aren't 301'd.
  config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  config.cache_store = :solid_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Set host to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = { host: "statuspulse.org", protocol: "https" }

  # Outgoing mail via the Mailgun HTTP API (see lib/mailgun_api_delivery.rb).
  # The API is used rather than SMTP because AWS restricts outbound SMTP on
  # Lightsail/EC2 by default, whereas this is ordinary HTTPS on 443.
  #
  # delivery_method must be set explicitly — the default resolves to localhost:25,
  # and since raise_delivery_errors defaults to true in production, the weekly
  # digest job would raise Errno::ECONNREFUSED on every run.
  # Credentials are registered in config/initializers/mailgun.rb — see the note
  # there about load-hook ordering.
  config.action_mailer.delivery_method = :mailgun_api

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Enable DNS rebinding protection and other `Host` header attacks.
  config.hosts = [
    "statuspulse.org",
    "www.statuspulse.org"
  ]

  # Skip DNS rebinding protection for the default health check endpoint. Required:
  # the container healthcheck hits localhost/up, which is not in the allowlist above.
  config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
