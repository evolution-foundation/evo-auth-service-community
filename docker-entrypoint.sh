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
# CRM-216: the database is only CREATED when it does not already exist.
#
# The self-hosted box connects as `evo_app`, which is NOCREATEDB *by design* —
# it is the live role behind RLS. Running `db:create` unconditionally made
# Postgres reject it with "permission denied to create database" on every one
# of the 30 attempts, and the entrypoint aborted the boot. Since the whole
# stack declares `depends_on: auth (service_healthy)`, that took the entire box
# down: following the guide, no operator could install it.
#
# Note that `db:create` does NOT survive this on its own. Rails only converts
# the failure into a harmless "already exists" when Postgres answers
# PG::DuplicateDatabase; a NOCREATEDB role never gets that far, because the
# privilege check comes first and raises PG::InsufficientPrivilege instead.
# Changing the database owner does not help either: CREATE DATABASE requires
# the CREATEDB *role attribute*, not ownership.
database_reachable() {
  bundle exec rails db:version >/dev/null 2>&1
}

if [ "${RUN_MIGRATIONS:-true}" != "false" ]; then
  echo "[evo-auth-entrypoint] Preparing database..."
  n=0
  until [ "$n" -ge 30 ]; do
    if database_reachable; then
      # The database is there: migrate only. Asking to create it here is what
      # broke the self-hosted box, and it could never succeed anyway.
      if bundle exec rails db:migrate; then
        echo "[evo-auth-entrypoint] Migrations applied."
        break
      fi
    else
      # Not reachable. Either the server is still starting (the reason this
      # retry loop exists) or the database was never created — the fresh-install
      # case, where the connecting role usually is allowed to create it.
      echo "[evo-auth-entrypoint] Database not reachable; attempting to create it..."
      if bundle exec rails db:create && bundle exec rails db:migrate; then
        echo "[evo-auth-entrypoint] Database created and migrations applied."
        break
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
    # CRM-216: the failure that cost an entire box install was indistinguishable
    # from "Postgres is slow to start". If we never reached the database, say what
    # an operator can actually act on — the create may be refused on purpose.
    if ! database_reachable; then
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
