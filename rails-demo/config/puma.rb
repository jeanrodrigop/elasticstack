port ENV.fetch("PORT", 3000)
environment ENV.fetch("RAILS_ENV", "production")

# Single mode (no forked workers) keeps one APM agent instance in the process.
workers 0
max_threads = ENV.fetch("RAILS_MAX_THREADS", 5).to_i
threads max_threads, max_threads

# Serve config.ru from the app root.
rackup "config.ru"
