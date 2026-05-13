# frozen_string_literal: true

# Backfills new template-bundle permissions added in
# ResourceActionsConfig (templates.read, templates.export, templates.import)
# to already-bootstrapped installations.
#
# New installations pick these up automatically via db/seeds/rbac.rb
# when SetupBootstrapService runs; existing installations skip the seed
# after bootstrap, so we need a data migration.
#
# Idempotent: SELECT-before-INSERT, no-op if role missing (e.g. not yet
# bootstrapped — seed will handle it). Also assigns to super_admin so the
# installation owner can use the feature out of the box.
class AddTemplatePermissionsToAccountOwner < ActiveRecord::Migration[7.1]
  PERMISSIONS = %w[
    templates.read
    templates.export
    templates.import
  ].freeze

  ROLE_KEYS = %w[account_owner super_admin].freeze

  def up
    # Fresh installs hit this migration before init_schema (timestamp 9025…)
    # has run, so `roles` may not exist yet — seed will cover it later.
    return unless ActiveRecord::Base.connection.table_exists?(:roles)

    ROLE_KEYS.each do |role_key|
      role = Role.find_by(key: role_key)
      next unless role # bootstrapped install without this role — seed will cover it

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
