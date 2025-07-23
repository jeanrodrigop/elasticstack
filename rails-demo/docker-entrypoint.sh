#!/usr/bin/env sh
set -e

echo "[entrypoint] preparing database..."

# Postgres is gated by compose (depends_on: service_healthy), but create+migrate
# defensively with a retry in case the app wins the race on a cold start.
bundle exec rake db:create 2>/dev/null || true

n=0
until bundle exec rake db:migrate; do
  n=$((n + 1))
  if [ "$n" -ge 10 ]; then
    echo "[entrypoint] db:migrate failed after $n attempts" >&2
    exit 1
  fi
  echo "[entrypoint] database not ready, retrying in 3s... ($n)"
  sleep 3
done

echo "[entrypoint] starting: $*"
exec "$@"
