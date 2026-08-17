# frozen_string_literal: true

# Paired data-migration for the agent-role RBAC hardening (cards #178 / #181 / #182).
#
# Three coordinated changes to the default `agent` role seed (db/seeds/rbac.rb):
#   1. REVOKE conversations.read_all — secure-by-default inbox visibility. Without it,
#      User#assigned_inboxes returns only the inboxes the agent is a member of (an
#      agent with no membership sees nothing until assigned). Admins/account_owner
#      keep full visibility via administrator?, so they are unaffected.
#   2. REVOKE destructive/admin keys that are not part of attendance:
#      conversations.delete, contacts.delete, pipeline_stages.delete, and
#      teams.create/update/delete (team management, incl. team_members via
#      teams.update).
#   3. GRANT pipeline_items.update — the agent moves/creates cards via this dedicated
#      key (gated in the CRM by PipelinePolicy#update_items?), instead of the
#      manager-level pipelines.update. Deploy TOGETHER with the CRM change that gates
#      PipelineItemsController by pipeline_items.update, and with the catalog change
#      that adds the pipeline_items resource to ResourceActionsConfig.
#
# Fresh installs pick up the trimmed seed; already-bootstrapped installations skip
# the seed, so this migration reconciles the EXISTING system `agent` role. Only the
# system role (key = 'agent') is touched — custom roles (e.g. per-client copies) that
# an admin deliberately created are left intact.
#
# Pattern mirrors RevokeAdminSettingsPermissionsFromAgentRole (20260626130000):
# idempotent (destroy_all / exists-before-create), no-op when table/role is absent.
#
# ROLLBACK IS LOSSY — `down` re-grants the revoked keys and removes the granted one
# as a best-effort restore; it does not track per-key provenance. Re-running
# db/seeds/rbac.rb is the supported repair after a rollback.
class HardenAgentRolePermissions < ActiveRecord::Migration[7.1]
  AGENT_ROLE_KEY = 'agent'

  # Removed from the attendance role: see-all-inboxes + destructive/admin actions.
  REVOKED_PERMISSIONS = %w[
    conversations.read_all
    conversations.delete
    contacts.delete
    pipeline_stages.delete
    teams.create
    teams.update
    teams.delete
  ].freeze

  # Added: dedicated card-write key (replaces relying on pipelines.update).
  GRANTED_PERMISSIONS = %w[
    pipeline_items.update
  ].freeze

  def up
    return unless ActiveRecord::Base.connection.table_exists?(:roles)

    role = Role.find_by(key: AGENT_ROLE_KEY)
    return unless role

    role.role_permissions_actions
        .where(permission_key: REVOKED_PERMISSIONS)
        .destroy_all

    grant(role, GRANTED_PERMISSIONS)
  end

  def down
    return unless ActiveRecord::Base.connection.table_exists?(:roles)

    role = Role.find_by(key: AGENT_ROLE_KEY)
    return unless role

    role.role_permissions_actions
        .where(permission_key: GRANTED_PERMISSIONS)
        .destroy_all

    grant(role, REVOKED_PERMISSIONS)
  end

  private

  def grant(role, keys)
    keys.each do |permission_key|
      # create! validates against the current catalog; skip keys that are not in it
      # (e.g. removed later) rather than raise, and skip already-present keys.
      next unless ResourceActionsConfig.valid_permission?(permission_key)
      next if role.role_permissions_actions.exists?(permission_key: permission_key)

      role.role_permissions_actions.create!(permission_key: permission_key)
    end
  end
end
