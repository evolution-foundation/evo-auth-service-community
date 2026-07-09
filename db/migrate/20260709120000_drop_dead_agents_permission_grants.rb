# frozen_string_literal: true

# EVO-2072 — ubiquitous language: drop the dead twin `agents.*` grants.
#
# The catalog no longer defines `agents` (it duplicated `ai_agents`). Its ONLY
# enforcement was the CRM AgentsController, which proxies AI-agent CRUD to
# evo-core forwarding the caller's own token (app/services/evo_ai_core_service.rb),
# and evo-core gates every /agents route with `ai_agents.*` (pkg/agent/handler,
# mounted in cmd/api/main.go). So a role holding `agents.read` but not
# `ai_agents.read` cleared the CRM door and was still refused by the core: the
# grant conferred NO effective capability.
#
# This migration therefore only DELETES those dead rows. It deliberately does NOT
# rewrite them into `ai_agents.*`. Promoting them would hand real AI-agent
# management — including `ai_agents.delete`, enforced across 19 core routes — to
# any custom role whose admin merely ticked the misleadingly-named "Agents" box,
# which is exactly the confusion this story exists to remove. That would be a
# silent privilege escalation and would break the zero-enforcement-change
# guarantee (NFR1). Roles meant to manage AI agents already hold `ai_agents.*`
# and are left untouched.
#
# Raw SQL on purpose: `agents.*` is no longer a valid catalog key, and a data
# migration must not depend on the catalog it happens to ship with — the same trap
# that forced a `valid_permission?` guard onto 20260626130000#down.
#
# Idempotent (deleting nothing is a no-op) and safe on fresh installs.
class DropDeadAgentsPermissionGrants < ActiveRecord::Migration[7.1]
  TABLE = 'role_permissions_actions'

  # The trailing dot is what keeps `ai_agents.*`, `agent_bots.*` and
  # `agent_apikeys.*` out of the match — LIKE is anchored to the whole value, so
  # only keys literally starting with `agents.` are deleted.
  DEAD_PREFIX = 'agents.'

  def up
    return unless connection.table_exists?(TABLE)

    execute(ActiveRecord::Base.sanitize_sql_array([
      "DELETE FROM #{TABLE} WHERE permission_key LIKE ?",
      "#{ActiveRecord::Base.sanitize_sql_like(DEAD_PREFIX)}%"
    ]))
  end

  def down
    # Non-reversible cleanup, mirroring CleanupRbacCatalogGrants#down: the deleted
    # grants named a key the catalog no longer validates, so they cannot be
    # re-created. Re-run db/seeds/rbac.rb to repair after a rollback.
  end
end
