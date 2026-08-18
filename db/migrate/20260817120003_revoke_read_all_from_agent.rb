# frozen_string_literal: true

# Paired data-migration for CRM-181 — secure-by-default inbox visibility.
#
# The default `agent` role's seed used to grant conversations.read_all, which
# makes User#assigned_inboxes return every inbox. Removing it means the agent
# sees ONLY the inboxes it is a member of (none => it sees nothing until an admin
# assigns it). Admins/account_owner keep full visibility via administrator? and
# their own read_all grant, so they are unaffected.
#
# Why a data-migration and not seed-only: db/seeds/rbac.rb `destroy_all`s and
# recreates the agent role from the trimmed array on every run, and db:seed runs
# on every deploy (compose auth command; k8s/base/migrate-job.yaml). But an
# install that runs `db:migrate` WITHOUT `db:seed` would keep the stale grant —
# so this migration reconciles the EXISTING system `agent` role. Only the system
# role (key = 'agent') is touched — custom roles (per-client copies) are intact.
#
# OPERATOR NOTE (behaviour change): revoking read_all is only safe once inbox
# memberships exist. An agent user with zero inbox_members will see an EMPTY
# conversation/inbox list afterwards, with no auto-recovery (the old
# `inbox_members.empty? -> Inbox.all` degrade was removed on purpose — see
# evo-ai-crm-community app/models/user.rb#assigned_inboxes). Populate inbox_members
# for the agents that need visibility BEFORE this migration reaches the
# environment. To make the blast radius visible, `up` counts and logs how many
# agent-role users currently have zero inbox_members before revoking.
#
# ROLLBACK IS FORWARD-ONLY — `down` is a deliberate no-op. Re-granting read_all on
# rollback would be a privilege ESCALATION: a fresh install's agent never held the
# key, so recreating it would hand every inbox to a role that was designed not to
# see them. Restoring the pre-hardening grant, if ever truly needed, is an explicit
# admin action (and db:seed will NOT do it — the seed no longer lists the key).
class RevokeReadAllFromAgent < ActiveRecord::Migration[7.1]
  AGENT_ROLE_KEY = 'agent'

  REVOKED_PERMISSIONS = %w[
    conversations.read_all
  ].freeze

  def up
    return unless ActiveRecord::Base.connection.table_exists?(:roles)

    role = Role.find_by(key: AGENT_ROLE_KEY)
    return unless role

    log_agents_without_inbox_membership(role)

    role.role_permissions_actions
        .where(permission_key: REVOKED_PERMISSIONS)
        .destroy_all
  end

  # Intentionally a no-op — see the header. Rolling back must NOT re-grant read_all.
  def down; end

  private

  # Best-effort operational telemetry: how many agent-role users will lose their
  # conversation list because they have no inbox membership yet. inbox_members is
  # a CRM table living in the same shared database; guarded so a pure-auth install
  # (or any query hiccup) never fails the migration. Every path says something —
  # silence would read as "nothing to worry about" when it means "not assessed".
  def log_agents_without_inbox_membership(role)
    conn = ActiveRecord::Base.connection
    unless conn.table_exists?(:user_roles) && conn.table_exists?(:inbox_members)
      say 'CRM-181: inbox_members is not present in this database — blast radius NOT assessed. ' \
          'Verify inbox memberships from the CRM side before relying on this deploy.', true
      return
    end

    role_id = conn.quote(role.id)
    # Savepoint: on Postgres a failed statement aborts the whole transaction, so
    # without it the rescue below could not keep its promise — the revoke that
    # follows would die with PG::InFailedSqlTransaction (CRM-194).
    # `requires_new: true` is load-bearing only under db:migrate (joinable ddl
    # transaction); the spec's fixture transaction is non-joinable, so dropping it
    # would keep the suite green and break production.
    total = conn.transaction(requires_new: true) do
      conn.select_value(<<~SQL.squish)
        SELECT COUNT(*) FROM users u
        JOIN user_roles ur ON ur.user_id = u.id
        WHERE ur.role_id = #{role_id}
          AND NOT EXISTS (SELECT 1 FROM inbox_members im WHERE im.user_id = u.id)
      SQL
    end.to_i

    if total.positive?
      say "CRM-181: #{total} agent-role user(s) have ZERO inbox memberships and will " \
          'see an EMPTY conversation list after read_all is revoked. Populate inbox_members ' \
          'for them BEFORE relying on this deploy.', true
    else
      say 'CRM-181: all agent-role users have at least one inbox membership — safe to revoke read_all.', true
    end
  rescue StandardError => e
    say "CRM-181: could not count agents without inbox membership (#{e.class}: #{e.message}); revoking read_all anyway.", true
  end
end
