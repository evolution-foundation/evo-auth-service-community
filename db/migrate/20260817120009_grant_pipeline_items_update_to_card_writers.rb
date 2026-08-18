# frozen_string_literal: true

# Paired data-migration for CRM-178 (dedicated pipeline-card write key).
#
# Card writes used to authorize against the manager-level pipelines.update; the CRM
# gate (PipelinePolicy#update_items?) now requires pipeline_items.update. Deploy
# TOGETHER with:
#   - the ResourceActionsConfig change that adds the pipeline_items resource, and
#   - the evo-ai-crm-community change that gates PipelineItemsController by
#     pipeline_items.update.
#
# Version 20260817120009 — above the already-merged CRM-181/182/190 migrations
# (120003/120005/120007) so a `db:schema:load` install (schema at 120007) does NOT
# mark it applied-without-running via assume_migrated_upto_version.
#
# Fresh installs pick up the key from the trimmed seed (db/seeds/rbac.rb). Already
# up-and-running installs do NOT re-run the seed on a plain `db:migrate`, so the
# backfill has to happen here, and it covers TWO groups:
#   - the system `agent` role, which gains card writes for the first time (the point
#     of the card), and
#   - every role that ALREADY holds pipelines.update, system or custom. Those roles
#     can move/create cards TODAY; without this the gate split silently takes it away
#     from them on upgrade. Granting the new key preserves exactly the reach they had
#     — it is not an expansion. Same shape as
#     AddConversationsImportPermissionToExistingRoles (20260623130000).
#
# This is an ADDITIVE grant, so `down` cleanly reverses it: removing a permission
# the migration itself created is not a privilege change to any pre-existing state.
class GrantPipelineItemsUpdateToCardWriters < ActiveRecord::Migration[7.1]
  # Roles that get the key regardless of what they already hold.
  SEEDED_ROLE_KEYS = %w[agent].freeze

  # Holding this key means the role can already write cards, so it must keep doing so.
  SUPERSEDED_PERMISSION = 'pipelines.update'

  GRANTED_PERMISSIONS = %w[
    pipeline_items.update
  ].freeze

  def up
    return unless ActiveRecord::Base.connection.table_exists?(:roles)

    target_roles.each do |role|
      GRANTED_PERMISSIONS.each do |permission_key|
        next unless ResourceActionsConfig.valid_permission?(permission_key)
        next if role.role_permissions_actions.exists?(permission_key: permission_key)

        role.role_permissions_actions.create!(permission_key: permission_key)
      end
    end
  end

  def down
    return unless ActiveRecord::Base.connection.table_exists?(:roles)

    target_roles.each do |role|
      role.role_permissions_actions
          .where(permission_key: GRANTED_PERMISSIONS)
          .destroy_all
    end
  end

  private

  def target_roles
    seeded_ids = Role.where(key: SEEDED_ROLE_KEYS).ids
    card_writer_ids = Role.joins(:role_permissions_actions)
                          .where(role_permissions_actions: { permission_key: SUPERSEDED_PERMISSION })
                          .ids

    Role.where(id: seeded_ids | card_writer_ids)
  end
end
