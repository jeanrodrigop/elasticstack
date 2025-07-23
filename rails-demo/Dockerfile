FROM ruby:3.3-slim

# build-essential + libpq-dev: compile the pg and puma native extensions.
# libyaml-dev: required by psych. curl: used by the container healthcheck.
RUN apt-get update -qq \
    && apt-get install -y --no-install-recommends build-essential libpq-dev libyaml-dev curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install gems first so this layer is cached across app-code changes.
COPY Gemfile ./
RUN bundle install

# App code.
COPY . .
RUN chmod +x docker-entrypoint.sh

ENV RAILS_ENV=production \
    RAILS_LOG_TO_STDOUT=1 \
    PORT=3000

EXPOSE 3000

# Entrypoint waits for / migrates the DB, then runs the CMD (Puma).
ENTRYPOINT ["./docker-entrypoint.sh"]
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
