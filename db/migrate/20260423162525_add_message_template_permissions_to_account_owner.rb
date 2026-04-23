# frozen_string_literal: true

# Backfills new message-template permissions added in
# ResourceActionsConfig (inboxes.update_message_template,
# inboxes.delete_message_template) to already-bootstrapped installations.
#
# New installations pick these up automatically via db/seeds/rbac.rb
# when SetupBootstrapService runs; existing installations skip the seed
# after bootstrap, so we need a data migration.
#
# Idempotent: SELECT-before-INSERT, no-op if role missing (e.g. not yet
# bootstrapped — seed will handle it).
class AddMessageTemplatePermissionsToAccountOwner < ActiveRecord::Migration[7.1]
  PERMISSIONS = %w[
    inboxes.update_message_template
    inboxes.delete_message_template
  ].freeze

  def up
    role = Role.find_by(key: 'account_owner')
    return unless role # fresh install — seed will cover it

    PERMISSIONS.each do |permission_key|
      next if role.role_permissions_actions.exists?(permission_key: permission_key)

      role.role_permissions_actions.create!(permission_key: permission_key)
    end
  end

  def down
    role = Role.find_by(key: 'account_owner')
    return unless role

    role.role_permissions_actions.where(permission_key: PERMISSIONS).destroy_all
  end
end
