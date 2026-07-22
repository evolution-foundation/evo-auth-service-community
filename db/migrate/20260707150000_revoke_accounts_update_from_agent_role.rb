# frozen_string_literal: true

# The default `agent` role's seed granted `accounts.update` alongside
# `accounts.read`. Account settings (name/domain/support_email/locale/
# settings/custom_attributes) are an administrative surface — its only
# frontend consumer is the Settings > Account screen — so an attendant must
# not be able to rewrite them. Now that PATCH /api/v1/account enforces
# `accounts.update`, holding the key would let the default agent through.
#
# Fresh installs pick up the trimmed seed; already-bootstrapped installations
# skip the seed, so this migration strips the key from the EXISTING system
# `agent` role. Only the system role (key = 'agent') is touched — custom roles
# an admin deliberately granted `accounts.update` to are left intact.
# `accounts.read` stays (the frontend loads the account at boot).
#
# Pattern mirrors RevokeAdminSettingsPermissionsFromAgentRole (20260626130000):
# idempotent, no-op when the table/role is absent. ROLLBACK re-grants the key
# as a best-effort restore; re-running db/seeds/rbac.rb is the supported
# repair after a rollback.
class RevokeAccountsUpdateFromAgentRole < ActiveRecord::Migration[7.1]
  AGENT_ROLE_KEY = 'agent'
  REVOKED_PERMISSIONS = %w[accounts.update].freeze

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
