# frozen_string_literal: true

# Paired data-migration for EVO-1938 (residual RBAC leak).
#
# The default `agent` role's seed (db/seeds/rbac.rb) used to grant administrative
# Settings resources (AI Agents/Bots/API keys/folders/sessions, Teams,
# Integrations, Channels, Working Hours, Segments, Journeys, Campaigns). The
# frontend routes/menu and the CRM controllers already gate by these permission
# keys, so an `agent` holding them sees and manages admin-only Settings screens.
#
# Fresh installs pick up the trimmed seed; already-bootstrapped installations skip
# the seed, so this migration strips the keys from the EXISTING system `agent`
# role. Only the system role (key = 'agent') is touched — custom roles an admin
# deliberately granted these to are left intact.
#
# Operational resources used inside conversations (labels, canned_responses,
# macros, message_templates) are deliberately NOT revoked — removing them would
# break the chat. Their use-vs-manage split is the EVO-1955 follow-up.
#
# Pattern mirrors GrantRbacSplitPermissionsToExistingRoles (20260622120001):
# idempotent (exists-before-destroy), no-op when the table/role is absent.
#
# ROLLBACK IS LOSSY — `down` re-grants the keys to the system `agent` role as a
# best-effort restore of the pre-migration state; it does not track per-key
# provenance. Re-running db/seeds/rbac.rb is the supported repair after a rollback.
class RevokeAdminSettingsPermissionsFromAgentRole < ActiveRecord::Migration[7.1]
  AGENT_ROLE_KEY = 'agent'

  # Administrative Settings resources revoked from the default agent (EVO-1938).
  REVOKED_PERMISSIONS = %w[
    agents.read agents.create agents.update agents.delete
    oauth_agents.read oauth_agents.create oauth_agents.update oauth_agents.delete
    agent_bots.read agent_bots.create agent_bots.update agent_bots.delete agent_bots.avatar
    agent_apikeys.read agent_apikeys.create agent_apikeys.update agent_apikeys.delete
    agent_folders.read agent_folders.create agent_folders.update agent_folders.delete
    agent_shared_folders.read agent_shared_folders.create agent_shared_folders.update agent_shared_folders.delete
    ai_chat_sessions.read ai_chat_sessions.create ai_chat_sessions.update ai_chat_sessions.delete
    channels.read
    integrations.read
    working_hours.read working_hours.create working_hours.update working_hours.delete
    segments.read
    journeys.read
    campaigns.read
  ].freeze

  def up
    return unless ActiveRecord::Base.connection.table_exists?(:roles)

    role = Role.find_by(key: AGENT_ROLE_KEY)
    return unless role

    role.role_permissions_actions
        .where(permission_key: REVOKED_PERMISSIONS)
        .destroy_all
  end

  def down
    return unless ActiveRecord::Base.connection.table_exists?(:roles)

    role = Role.find_by(key: AGENT_ROLE_KEY)
    return unless role

    REVOKED_PERMISSIONS.each do |permission_key|
      next if role.role_permissions_actions.exists?(permission_key: permission_key)

      role.role_permissions_actions.create!(permission_key: permission_key)
    end
  end
end
