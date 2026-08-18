# frozen_string_literal: true

# Paired data-migration for CRM-178 (dedicated pipeline-card write key).
#
# The default `agent` role gains pipeline_items.update — the key the CRM gate
# (PipelinePolicy#update_items?) now requires to move/create/edit cards, instead
# of leaning on the manager-level pipelines.update. Deploy TOGETHER with:
#   - the ResourceActionsConfig change that adds the pipeline_items resource, and
#   - the evo-ai-crm-community change that gates PipelineItemsController by
#     pipeline_items.update.
#
# Version 20260817120009 — above the already-merged CRM-181/182/190 migrations
# (120003/120005/120007) so a `db:schema:load` install (schema at 120007) does NOT
# mark it applied-without-running via assume_migrated_upto_version.
#
# Fresh installs pick up the key from the trimmed seed (db/seeds/rbac.rb). Already
# up-and-running installs do NOT re-run the seed on a plain `db:migrate`, so this
# migration grants the key to the EXISTING system `agent` role. Only the system
# role (key = 'agent') is touched — custom roles (per-client copies) are left intact.
#
# This is an ADDITIVE grant, so `down` cleanly reverses it: removing a permission
# the migration itself created is not a privilege change to any pre-existing state.
class GrantPipelineItemsUpdateToAgent < ActiveRecord::Migration[7.1]
  AGENT_ROLE_KEY = 'agent'

  GRANTED_PERMISSIONS = %w[
    pipeline_items.update
  ].freeze

  def up
    return unless ActiveRecord::Base.connection.table_exists?(:roles)

    role = Role.find_by(key: AGENT_ROLE_KEY)
    return unless role

    GRANTED_PERMISSIONS.each do |permission_key|
      next unless ResourceActionsConfig.valid_permission?(permission_key)
      next if role.role_permissions_actions.exists?(permission_key: permission_key)

      role.role_permissions_actions.create!(permission_key: permission_key)
    end
  end

  def down
    return unless ActiveRecord::Base.connection.table_exists?(:roles)

    role = Role.find_by(key: AGENT_ROLE_KEY)
    return unless role

    role.role_permissions_actions
        .where(permission_key: GRANTED_PERMISSIONS)
        .destroy_all
  end
end
