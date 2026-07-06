#!/usr/bin/env bash
# EVO-1999 — Run migrations on image boot, in ANY orchestrator.
#
# Why: platforms like CapRover deploy from the image alone and start the
# container with the image ENTRYPOINT/CMD, IGNORING the docker-compose
# `command:`/`entrypoint:` (where db:migrate used to run). Without this, every
# image update leaves migrations pending and the web boots with a stale schema
# (e.g. 500s on routes that depend on new columns).
#
# RUN_MIGRATIONS gate (default 'true' = fail-safe: never boot with a stale
# schema). Set RUN_MIGRATIONS=false on *-sidekiq services to avoid migrating
# twice. Rails db:migrate takes a Postgres advisory lock, so it is safe even if
# more than one process tries to migrate at the same time.
set -e

# Compare against "false" (not == "true") so that TRUE/1/typos still migrate —
# the fail-safe default must never be silently disabled by a malformed value.
if [ "${RUN_MIGRATIONS:-true}" != "false" ]; then
  echo "[evo-auth-entrypoint] Preparing database (db:create + db:migrate)..."
  n=0
  until [ "$n" -ge 30 ]; do
    if bundle exec rails db:create db:migrate; then
      echo "[evo-auth-entrypoint] Migrations applied."
      break
    fi
    n=$((n + 1))
    echo "[evo-auth-entrypoint] database unavailable or migrate failed — attempt ${n}/30; waiting 2s..."
    sleep 2
  done
  # Fail-safe: never boot with a stale schema. If migrations did not complete
  # after all attempts, exit non-zero and let the orchestrator restart policy
  # retry, instead of starting Puma against an outdated database.
  if [ "$n" -ge 30 ]; then
    echo "[evo-auth-entrypoint] ERROR: migrations did not complete after 30 attempts; aborting boot." >&2
    exit 1
  fi
else
  echo "[evo-auth-entrypoint] RUN_MIGRATIONS=${RUN_MIGRATIONS} — skipping migrations."
fi

exec "$@"
