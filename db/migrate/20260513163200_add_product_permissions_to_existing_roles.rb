# frozen_string_literal: true

# Backfills the new `products.*` permissions added in ResourceActionsConfig
# (products.read, products.create, products.update, products.delete) to
# already-bootstrapped installations.
#
# New installations pick these up automatically via db/seeds/rbac.rb when
# SetupBootstrapService runs; existing installations skip the seed after
# bootstrap, so we need a data migration.
#
# Pattern mirrors AddMessageTemplatePermissionsToAccountOwner
# (20260423162525) — same idempotency guarantees (SELECT-before-INSERT,
# no-op when the role doesn't exist yet).
class AddProductPermissionsToExistingRoles < ActiveRecord::Migration[7.1]
  PERMISSIONS = %w[
    products.read
    products.create
    products.update
    products.delete
  ].freeze

  # Roles that should automatically receive the full set of product
  # permissions on upgrade. `agent` is intentionally omitted — operators
  # see/manage the catalog by default; agents that should manage it can be
  # granted the permissions manually via the role editor.
  ROLE_KEYS = %w[super_admin account_owner].freeze

  def up
    # Fresh installs hit this migration before init_schema (timestamp 9025…)
    # has run, so `roles` may not exist yet — seed will cover it later.
    return unless ActiveRecord::Base.connection.table_exists?(:roles)

    ROLE_KEYS.each do |role_key|
      role = Role.find_by(key: role_key)
      next unless role # bootstrapped install missing this role — seed will cover it

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
