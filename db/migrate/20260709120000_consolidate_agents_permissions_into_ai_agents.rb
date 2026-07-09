# frozen_string_literal: true

# EVO-2072 — ubiquitous language: consolidate the dead twin `agents.*` into
# `ai_agents.*` on existing roles.
#
# `agents` was a duplicate resource that only ever gated the CRM AgentsController,
# which proxies AI-agent CRUD to evo-core (EvoAiCoreService.list_agents/...). The
# frontend already gates that screen with `can('ai_agents')`, and the catalog now
# drops `agents` entirely (Path A). This migration rewrites the grants so no role
# loses the capability: for every `agents.<action>` a role holds, it gains the
# equivalent `ai_agents.<action>` (if missing) and the `agents.*` row is removed.
#
# Idempotent (SELECT-before-INSERT, delete is a no-op when nothing matches) and
# safe on fresh installs (the `roles` table may not exist yet — the seed covers
# those). Disjoint from the EVO-2070 team_members.*->teams.* migration: this one
# only touches the `agents.*` namespace, so the two coexist without double-touch.
#
# ROLLBACK IS NOT SUPPORTED. `up` is lossy on purpose:
#   * the target `ai_agents.*` already pre-exists on most roles (super_admin /
#     account_owner seed it via all_permission_keys), so a symmetric `down` that
#     stripped `ai_agents.*` would destroy grants this migration never added —
#     a real capability regression.
#   * re-adding `agents.*` is pointless: it is a dead key the catalog no longer
#     validates (RolePermissionsAction#permission_key_must_be_valid would reject
#     it on any subsequent save).
# Re-running db/seeds/rbac.rb is the supported repair path if ever needed.
class ConsolidateAgentsPermissionsIntoAiAgents < ActiveRecord::Migration[7.1]
  ACTIONS = %w[read create update delete].freeze

  def up
    # Fresh installs hit this migration before init_schema has run, so `roles`
    # may not exist yet — the seed will cover them later.
    return unless ActiveRecord::Base.connection.table_exists?(:roles)

    Role.find_each do |role|
      ACTIONS.each do |action|
        old_key = "agents.#{action}"
        next unless role.role_permissions_actions.exists?(permission_key: old_key)

        new_key = "ai_agents.#{action}"
        # Grant the target first (idempotent), then drop the dead key. `delete_all`
        # skips validation, which is required: `agents.*` is no longer a valid key.
        grant(role, new_key)
        role.role_permissions_actions.where(permission_key: old_key).delete_all
      end
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          'agents.* -> ai_agents.* consolidation is one-way; re-run db/seeds/rbac.rb to repair.'
  end

  private

  def grant(role, permission_key)
    return if role.role_permissions_actions.exists?(permission_key: permission_key)

    role.role_permissions_actions.create!(permission_key: permission_key)
  end
end
