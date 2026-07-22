# frozen_string_literal: true

# The CRM gates integration event processing (hooks#process_event and the
# global openai#process_event) on `integrations.execute`, but the key was
# absent from the catalog: RolePermissionsAction validates keys against
# ResourceActionsConfig, so no role could ever hold it and the endpoints
# denied every user. The catalog now registers integrations.execute; fresh
# installs pick it up via db/seeds/rbac.rb (account_owner receives every
# non-exclusive catalog key), and this migration grants it to the existing
# admin system roles. The default agent does not receive it — the consumers
# live in the admin-only AI-agent configuration screens.
#
# Pattern mirrors GrantRbacSplitPermissionsToExistingRoles (20260622120001):
# idempotent (exists-before-create), no-op when the table/role is absent.
# `down` strips the key from the two system roles; re-running the seed is the
# supported repair after a rollback.
class GrantIntegrationsExecuteToAdminRoles < ActiveRecord::Migration[7.1]
  PERMISSION_KEY = 'integrations.execute'
  ADMIN_ROLE_KEYS = %w[account_owner super_admin].freeze

  def up
    return unless ActiveRecord::Base.connection.table_exists?(:roles)

    ADMIN_ROLE_KEYS.each do |role_key|
      role = Role.find_by(key: role_key)
      next unless role
      next if role.role_permissions_actions.exists?(permission_key: PERMISSION_KEY)

      role.role_permissions_actions.create!(permission_key: PERMISSION_KEY)
    end
  end

  def down
    return unless ActiveRecord::Base.connection.table_exists?(:roles)

    ADMIN_ROLE_KEYS.each do |role_key|
      role = Role.find_by(key: role_key)
      next unless role

      role.role_permissions_actions
          .where(permission_key: PERMISSION_KEY)
          .destroy_all
    end
  end
end
