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
#
# CRM-216: only CREATE the database when it is not already there. `evo_app` is
# NOCREATEDB by design (the live role behind RLS), and db:create cannot survive
# that on its own: the privilege check raises PG::InsufficientPrivilege before
# Postgres ever answers DuplicateDatabase, and CREATE DATABASE needs the
# CREATEDB *role attribute*, not ownership.
database_reachable() {
  bundle exec rails db:version >/dev/null 2>&1
}

if [ "${RUN_MIGRATIONS:-true}" != "false" ]; then
  echo "[evo-auth-entrypoint] Preparing database..."
  n=0
  reached=0
  until [ "$n" -ge 30 ]; do
    # Probe at most once: after the first success the database is known to be
    # there, so re-probing each attempt only buys another Rails boot.
    if [ "$reached" = 1 ] || database_reachable; then
      reached=1
      if bundle exec rails db:migrate; then
        echo "[evo-auth-entrypoint] Migrations applied."
        break
      fi
    else
      # Either the server is still starting (what the 30 attempts are for) or
      # this is a fresh install, where the role usually may create.
      echo "[evo-auth-entrypoint] Database not reachable; attempting to create it..."
      if bundle exec rails db:create; then
        reached=1
        if bundle exec rails db:migrate; then
          echo "[evo-auth-entrypoint] Database created and migrations applied."
          break
        fi
      fi
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
    # CRM-216: this failure read exactly like "Postgres is slow to start", so an
    # operator had no way to know the create was refused on purpose.
    if [ "$reached" = 0 ]; then
      echo "[evo-auth-entrypoint] The database was never reachable. If the role is NOCREATEDB" >&2
      echo "[evo-auth-entrypoint] (as evo_app is by design on the self-hosted box), this service" >&2
      echo "[evo-auth-entrypoint] cannot create it: CREATE DATABASE needs the CREATEDB role" >&2
      echo "[evo-auth-entrypoint] attribute, and changing the database owner does not grant it." >&2
      echo "[evo-auth-entrypoint] Create the database out-of-band, then restart this service." >&2
    fi
    exit 1
  fi
  # The installation owner (super_admin) has no RBAC bypass anywhere: their
  # access is entirely grant-backed. A catalog that grew since the install was
  # bootstrapped would silently 403 them on the new feature and hide the control
  # in the (data-driven) frontend. Converging the grant set here — after the
  # schema is up to date — makes the invariant self-healing on every deploy.
  # Idempotent and a no-op before bootstrap, so it never blocks boot: a failure
  # is reported but does not abort (a stale grant is degraded, not unsafe).
  echo "[evo-auth-entrypoint] Reconciling super_admin grants with the permission catalog..."
  if ! bundle exec rails rbac:reconcile_super_admin; then
    # Boot continues (a stale grant is degraded, not unsafe), but a drifted admin
    # is invisible — so the failure must not read like a passing boot.
    echo "[evo-auth-entrypoint] ===============================================================" >&2
    echo "[evo-auth-entrypoint] ERROR: super_admin grant reconciliation FAILED." >&2
    echo "[evo-auth-entrypoint] The installation owner may be missing permissions added to the" >&2
    echo "[evo-auth-entrypoint] catalog since this install was bootstrapped: the API will 403" >&2
    echo "[evo-auth-entrypoint] them on the affected features and the UI will hide the controls." >&2
    echo "[evo-auth-entrypoint] Repair with: bundle exec rails rbac:reconcile_super_admin" >&2
    echo "[evo-auth-entrypoint] Diagnose with: bundle exec rails rbac:check_super_admin_drift" >&2
    echo "[evo-auth-entrypoint] ===============================================================" >&2
  fi
else
  echo "[evo-auth-entrypoint] RUN_MIGRATIONS=${RUN_MIGRATIONS} — skipping migrations."
fi

exec "$@"
