# frozen_string_literal: true

# Paired data-migration for CRM-182 — least-privilege for the attendance role.
#
# The default `agent` role's seed granted destructive/admin keys that are not part
# of attendance. This revokes them from the EXISTING system `agent` role on upgrade:
#   - conversations.delete  — deleting a conversation is not attendance (closing is
#     conversations.toggle_status, kept).
#   - contacts.delete       — also gates contact_merge (destroys the mergee) and the
#     Contact bulk-delete.
#   - pipeline_stages.delete — destructive restructuring of the shared funnel.
#   - teams.create / teams.update / teams.delete — creating, renaming and deleting
#     teams, plus managing members via team_members (gated by teams.update), is a
#     manager/settings action. teams.read stays (the in-chat "Assign team" picker).
#
# Why a data-migration and not seed-only: db/seeds/rbac.rb `destroy_all`s and
# recreates the agent role from the trimmed array on every run, and db:seed runs on
# every deploy (compose auth command; k8s/base/migrate-job.yaml). But an install that
# runs `db:migrate` WITHOUT `db:seed` would keep the stale grants — so this migration
# reconciles the EXISTING system `agent` role. Only the system role (key = 'agent')
# is touched — custom roles (per-client copies) are left intact.
#
# ROLLBACK IS FORWARD-ONLY — `down` is a deliberate no-op. Re-granting these keys on
# rollback would be a privilege ESCALATION: a fresh install's agent never held them,
# so recreating them would hand delete/team-management powers to a role designed not
# to have them. Restoring the pre-hardening grant, if ever truly needed, is an
# explicit admin action (and db:seed will NOT do it — the seed no longer lists them).
class RevokeDestructiveKeysFromAgent < ActiveRecord::Migration[7.1]
  AGENT_ROLE_KEY = 'agent'

  REVOKED_PERMISSIONS = %w[
    conversations.delete
    contacts.delete
    pipeline_stages.delete
    teams.create
    teams.update
    teams.delete
  ].freeze

  def up
    return unless ActiveRecord::Base.connection.table_exists?(:roles)

    role = Role.find_by(key: AGENT_ROLE_KEY)
    return unless role

    role.role_permissions_actions
        .where(permission_key: REVOKED_PERMISSIONS)
        .destroy_all
  end

  # Intentionally a no-op — see the header. Rolling back must NOT re-grant these keys.
  def down; end
end
