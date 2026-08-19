# frozen_string_literal: true

# Paired data-migration for CRM-70 — use-vs-manage split for macros and message
# templates. Product decision (2026-08-18): the attendance role USES them in the
# chat (macros.read + macros.execute, message_templates.read) but does not MANAGE
# them; create/update and the Settings screens now belong to `<resource>.manage`,
# granted to admin and managing roles (GrantManageActionsToManagingRoles). Labels, canned
# responses and teams are untouched here: the agent manages the first two by the
# same decision, and teams write was already revoked (CRM-182).
#
# Why a data-migration and not seed-only: db/seeds/rbac.rb recreates the agent
# role from the trimmed array on every db:seed, but an install that runs
# `db:migrate` WITHOUT `db:seed` would keep the stale grants. Only the system role
# (key = 'agent') is touched — custom roles are left intact.
#
# ROLLBACK IS FORWARD-ONLY — `down` is a deliberate no-op: re-granting on rollback
# would be a privilege escalation for a fresh install whose agent never held them.
class RevokeManageWritesFromAgent < ActiveRecord::Migration[7.1]
  AGENT_ROLE_KEY = 'agent'

  REVOKED_PERMISSIONS = %w[
    macros.create
    macros.update
    message_templates.create
    message_templates.update
  ].freeze

  def up
    return unless ActiveRecord::Base.connection.table_exists?(:roles)

    role = Role.find_by(key: AGENT_ROLE_KEY)
    return unless role

    role.role_permissions_actions
        .where(permission_key: REVOKED_PERMISSIONS)
        .destroy_all
  end

  def down; end
end
