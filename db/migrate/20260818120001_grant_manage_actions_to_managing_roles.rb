# frozen_string_literal: true

# Grants the use-vs-manage keys `macros.manage`, `message_templates.manage` and
# `teams.manage` (CRM-70) to already-bootstrapped installations.
#
# The keys enter ResourceActionsConfig with this change. Deploys that run
# `db:seed` on boot regrant admin roles from the full catalog and pick them up;
# installs that only run `migrate` would not, and the Settings screens (now gated
# by `.manage`) would ship dark. Covers TWO groups:
#   - the admin roles, which get the keys regardless of what they hold, and
#   - every role, system OR custom, that can already manage the resource today.
#     CRM-70 is a gate split: `create`/`update` stop authorizing the write and
#     `.manage` starts. Without this backfill the split silently takes management
#     away from those roles on upgrade. Granting the new key preserves the reach
#     they had — same shape as GrantPipelineItemsUpdateToCardWriters (CRM-178).
#
# What counts as "can already manage" is per resource (SUPERSEDED_PERMISSIONS):
#   - macros / message_templates -> the create/update keys the CRM controllers
#     used to gate on.
#   - teams -> create/update/delete, NOT `teams.read`. The Teams screen is gated
#     by `teams.read` today, but that key is in User::BASIC_READ_PERMISSIONS — every
#     user holds it, so keying off it would hand `teams.manage` to everyone and
#     undo the card. A role that actually manages teams holds a team write.
#
# The system `agent` role is EXCLUDED even when it matches: it holds
# macros/message_templates create+update until RevokeManageWritesFromAgent
# (20260818120003) takes them, and losing them is the point of the card. The
# exclusion also makes this migration order-independent from that one.
#
# This is an ADDITIVE grant, so `down` cleanly reverses it: removing a permission
# the migration itself created is not a privilege change to any pre-existing state.
class GrantManageActionsToManagingRoles < ActiveRecord::Migration[7.1]
  # Roles that get every key regardless of what they already hold.
  SEEDED_ROLE_KEYS = %w[super_admin account_owner].freeze

  # The system role the card deliberately trims; never a backfill target.
  EXCLUDED_ROLE_KEYS = %w[agent].freeze

  # granted key => keys whose holders can already manage the resource today.
  SUPERSEDED_PERMISSIONS = {
    'macros.manage' => %w[macros.create macros.update],
    'message_templates.manage' => %w[message_templates.create message_templates.update],
    'teams.manage' => %w[teams.create teams.update teams.delete]
  }.freeze

  PERMISSIONS = SUPERSEDED_PERMISSIONS.keys.freeze

  def up
    return unless ActiveRecord::Base.connection.table_exists?(:roles)

    PERMISSIONS.each do |permission_key|
      next unless ResourceActionsConfig.valid_permission?(permission_key)

      target_roles(permission_key).each do |role|
        next if role.role_permissions_actions.exists?(permission_key: permission_key)

        role.role_permissions_actions.create!(permission_key: permission_key)
      end
    end
  end

  def down
    return unless ActiveRecord::Base.connection.table_exists?(:roles)

    PERMISSIONS.each do |permission_key|
      target_roles(permission_key).each do |role|
        role.role_permissions_actions.where(permission_key: permission_key).destroy_all
      end
    end
  end

  private

  # A create-only role also gains `update` here: `.manage` is one coarse key and
  # has no finer split. The alternative is taking management away entirely, which
  # is the regression this migration exists to prevent.
  def target_roles(permission_key)
    seeded_ids = Role.where(key: SEEDED_ROLE_KEYS).ids
    manager_ids = Role.joins(:role_permissions_actions)
                      .where(role_permissions_actions: { permission_key: SUPERSEDED_PERMISSIONS.fetch(permission_key) })
                      .where.not(key: EXCLUDED_ROLE_KEYS)
                      .ids

    Role.where(id: seeded_ids | manager_ids)
  end
end
