require_relative "boot"

# Load only the frameworks this API app needs (no Action View / Mailer / Cable).
require "rails"
require "active_model/railtie"
require "active_record/railtie"
require "action_controller/railtie"

# Requires pg, puma and elastic_apm. Because Rails is already loaded, the
# elastic-apm gem registers its Railtie here and auto-starts on `initialize!`.
Bundler.require(*Rails.groups)

# Plain Ruby class (lib/ isn't autoloaded in Rails 7.1), so require it ourselves.
require_relative "../lib/ecs_apm_formatter"

module RailsDemo
  class Application < Rails::Application
    config.load_defaults 7.1

    # API-only: no views, cookies or sessions.
    config.api_only = true

    # Eager load in production so any coding error fails fast at boot.
    config.eager_load = ENV.fetch("RAILS_ENV", "production") == "production"

    # Don't block requests by Host header (the load generator hits us by the
    # container name, not localhost).
    config.hosts.clear

    # Set explicitly so production never needs credentials / a master key.
    config.secret_key_base = ENV.fetch("SECRET_KEY_BASE", "0" * 64)

    # We never use the cache; keep it in-memory so no tmp/ dir is required.
    config.cache_store = :memory_store

    # --- Structured logging --------------------------------------------------
    # ECS-JSON to stdout, enriched with the current APM trace/transaction ids so
    # Kibana can correlate these logs with the trace that produced them.
    logger = ActiveSupport::Logger.new($stdout)
    logger.formatter = EcsApmFormatter.new
    config.logger = ActiveSupport::TaggedLogging.new(logger)
    config.log_level = ENV.fetch("LOG_LEVEL", "info").to_sym
  end
end
