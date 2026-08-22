# frozen_string_literal: true

# CRM-210 — grants `users.reset_password` on already bootstrapped installations,
# which skip db/seeds/rbac.rb. Narrower than the sibling grant migrations on
# purpose: it does NOT infer the key from users.update, because the catalog
# refuses to imply it at runtime. `down` is lossy — re-run the seed to repair.
class AddUsersResetPasswordToAdminRoles < ActiveRecord::Migration[7.1]
  PERMISSION_KEY = 'users.reset_password'

  # Only the two system roles that are administrative by definition.
  TARGET_ROLE_KEYS = %w[account_owner super_admin].freeze

  def up
    # Fresh installs run this before init_schema; the seed covers them later.
    return unless ActiveRecord::Base.connection.table_exists?(:roles)

    Role.where(key: TARGET_ROLE_KEYS).find_each do |role|
      next if role.role_permissions_actions.exists?(permission_key: PERMISSION_KEY)

      role.role_permissions_actions.create!(permission_key: PERMISSION_KEY)
    end
  end

  def down
    return unless ActiveRecord::Base.connection.table_exists?(:roles)

    Role.find_each do |role|
      role.role_permissions_actions.where(permission_key: PERMISSION_KEY).destroy_all
    end
  end
end
