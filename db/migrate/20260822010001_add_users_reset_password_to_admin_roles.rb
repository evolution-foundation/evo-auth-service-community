# frozen_string_literal: true

# CRM-210 — paired data-migration for the new `users.reset_password` key.
#
# Fresh installs get it from db/seeds/rbac.rb (account_owner receives every key
# not in `account_owner_exclusive`; super_admin receives all). Already
# bootstrapped installations skip the seed, so without this migration the button
# would 403 for everyone, including the account owner.
#
# DELIBERATELY NARROW — unlike AddProductPermissionsToExistingRoles and
# GrantRbacSplitPermissionsToExistingRoles, this migration does NOT use the
# "already administrative" heuristic (holds users.create/update/delete) to reach
# custom roles. Setting another user's password is account takeover: the key is
# standalone in ResourceActionsConfig precisely so that no other grant implies
# it, and inferring it from users.update here would smuggle in through the back
# door exactly what the catalog refuses to imply at runtime. Custom roles that
# should have it are granted it explicitly, in the role editor.
#
# `down` strips the key from every role. Rollback is lossy in the same sense as
# the migrations above: re-running db/seeds/rbac.rb is the supported repair for
# the system roles.
class AddUsersResetPasswordToAdminRoles < ActiveRecord::Migration[7.1]
  PERMISSION_KEY = 'users.reset_password'

  # Only the two system roles that are administrative by definition.
  TARGET_ROLE_KEYS = %w[account_owner super_admin].freeze

  def up
    # Fresh installs hit this migration before init_schema has run, so `roles`
    # may not exist yet — the seed covers them later.
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
