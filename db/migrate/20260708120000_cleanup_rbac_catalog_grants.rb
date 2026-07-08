# frozen_string_literal: true

# Paired data-migration for the RBAC catalog hygiene story (EVO-2070).
#
# resource_actions_config.rb dropped 16 dead/duplicated resources and
# consolidated two into survivors. On a fresh install db/seeds/rbac.rb already
# reflects the trimmed catalog; existing (already-bootstrapped) installations
# skip the seed, so their role_permissions_actions rows still carry grants for
# keys that are no longer valid. Those rows are harmless at runtime (the gate
# only ever asks about catalog keys) but they linger in the DB and would fail
# any future find_or_create_by! against the now-stricter validation. This
# migration reconciles the stored grants with the trimmed catalog.
#
# What `up` does, using delete_all/update to BYPASS the permission_key
# validation (the old keys are already invalid against the catalog):
#   1) Rewrite consolidated keys (team_members.* -> teams.*, permissions.read ->
#      roles.read). The rewrite is unique-index-safe: `index_role_perms_actions_unique`
#      is on (role_id, permission_key), so for a role that already holds the
#      target key we DELETE the stale row instead of updating it into a
#      duplicate; roles missing the target get an in-place UPDATE. Several old
#      keys collapse onto teams.update — processing the renames in order keeps
#      each step consistent with the rows the previous step produced.
#   2) Delete grants for the fully removed resources, matched by key prefix.
#
# super_admin/account_owner keep every real capability: teams.read/teams.update
# and roles.read all survive in the catalog, so the consolidation only trades
# names, never access. The removed prefixes gate nothing that is still routed.
#
# `down` is intentionally a NON-REVERSIBLE no-op: the removed/renamed grants
# referenced keys that no longer exist in the catalog, so re-adding them would
# reintroduce invalid rows. Re-running db/seeds/rbac.rb is the supported repair
# after any rollback.
class CleanupRbacCatalogGrants < ActiveRecord::Migration[7.1]
  TABLE = 'role_permissions_actions'

  # Keys whose resource was consolidated into a survivor. team_members is a
  # team-composition concern nested under teams (reads -> teams.read, mutations
  # -> teams.update); permissions was a single read that folds into roles.read.
  KEY_RENAMES = {
    'team_members.read'   => 'teams.read',
    'team_members.create' => 'teams.update',
    'team_members.update' => 'teams.update',
    'team_members.delete' => 'teams.update',
    'permissions.read'    => 'roles.read'
  }.freeze

  # Resources removed outright (dead feature, phantom controllers, or vestigial
  # twins repointed on the frontend). Every grant with one of these prefixes is
  # deleted. The prefixes contain `_`, which is a LIKE wildcard, so they are run
  # through sanitize_sql_like before matching (see #up step 2) — otherwise
  # e.g. `ai_mcp_servers.%` could match unrelated keys.
  # NOTE: ai_tools is intentionally absent — the EVO-2070 audit found it still
  # enforced by live processor endpoints, so it stays in the catalog (see story
  # Dev Agent Record). ai_mcp_servers has no backend enforcement and is removed.
  REMOVED_PREFIXES = %w[
    oauth_contacts. oauth_agents. oauth_pipelines. oauth_pipeline_stages.
    ai_folders. agent_folders. agent_shared_folders. agent_apikeys.
    ai_mcp_servers. channels. reports. live_reports. summary_reports.
  ].freeze

  def up
    # Fresh installs hit this migration before init_schema has run.
    return unless connection.table_exists?(TABLE)

    # 1) Rewrite consolidated keys, unique-index-safe.
    KEY_RENAMES.each do |old_key, new_key|
      # a) Drop stale rows where the role already holds the target key.
      execute(ActiveRecord::Base.sanitize_sql_array([
        "DELETE FROM #{TABLE} WHERE permission_key = ? " \
        "AND role_id IN (SELECT role_id FROM #{TABLE} WHERE permission_key = ?)",
        old_key, new_key
      ]))
      # b) Rename the remaining rows (these roles lack the target key).
      execute(ActiveRecord::Base.sanitize_sql_array([
        "UPDATE #{TABLE} SET permission_key = ?, updated_at = now() WHERE permission_key = ?",
        new_key, old_key
      ]))
    end

    # 2) Delete grants for fully removed resources. sanitize_sql_like escapes the
    #    `_`/`%` LIKE metacharacters in the prefix so only the literal resource
    #    name matches; the trailing `%` stays an intentional wildcard.
    REMOVED_PREFIXES.each do |prefix|
      execute(ActiveRecord::Base.sanitize_sql_array([
        "DELETE FROM #{TABLE} WHERE permission_key LIKE ?",
        "#{ActiveRecord::Base.sanitize_sql_like(prefix)}%"
      ]))
    end
  end

  def down
    # Non-reversible cleanup: the removed/renamed grants referenced keys that no
    # longer exist in the catalog. Intentionally does not re-add them; re-run
    # db/seeds/rbac.rb to repair after a rollback.
  end
end
