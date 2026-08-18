# frozen_string_literal: true

# Grants the use-vs-manage keys `macros.manage`, `message_templates.manage` and
# `teams.manage` (CRM-70) to already-bootstrapped admin roles.
#
# The keys enter ResourceActionsConfig with this change. Deploys that run
# `db:seed` on boot regrant admin roles from the full catalog and pick them up;
# installs that only run `migrate` would not, and the Settings screens (now gated
# by `.manage`) would ship dark for admins. Same SELECT-before-INSERT idempotency
# as AddAiCredentialsPermissionsToExistingRoles.
class GrantManageActionsToAdminRoles < ActiveRecord::Migration[7.1]
  PERMISSIONS = %w[
    macros.manage
    message_templates.manage
    teams.manage
  ].freeze

  # `agent` is intentionally omitted: the Settings screens are admin-only by
  # product decision (CRM-70); the agent keeps read/execute for the chat.
  ROLE_KEYS = %w[super_admin account_owner].freeze

  def up
    return unless ActiveRecord::Base.connection.table_exists?(:roles)

    ROLE_KEYS.each do |role_key|
      role = Role.find_by(key: role_key)
      next unless role

      PERMISSIONS.each do |permission_key|
        next if role.role_permissions_actions.exists?(permission_key: permission_key)

        role.role_permissions_actions.create!(permission_key: permission_key)
      end
    end
  end

  def down
    return unless ActiveRecord::Base.connection.table_exists?(:roles)

    ROLE_KEYS.each do |role_key|
      role = Role.find_by(key: role_key)
      next unless role

      role.role_permissions_actions.where(permission_key: PERMISSIONS).destroy_all
    end
  end
end
