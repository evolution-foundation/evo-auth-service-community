# frozen_string_literal: true

# Backfills the EVO-1557 permission `conversations.import` to roles on
# already-bootstrapped installations.
#
# New installations pick this up automatically via db/seeds/rbac.rb when
# SetupBootstrapService runs; existing installations skip the seed after
# bootstrap, and releases run `migrate` (not `seed`). Without this data
# migration the new endpoint `POST /api/v1/conversations/import` 403s for
# every role on prod — including super_admin (grant-backed, not bypassed) —
# until someone reruns the seed by hand.
#
# Pattern mirrors AddCrmFormsAndChatPagesPermissionsToExistingRoles
# (20260622210000) — same idempotency guarantees (SELECT-before-INSERT,
# no-op when the role is absent).
#
# `agent` is included here (unlike the B14 / products backfills) because the
# precedent action — `contacts.import` — is granted to the agent role by the
# seed, and conversations.import is the matching capability for the new
# data_type.
class AddConversationsImportPermissionToExistingRoles < ActiveRecord::Migration[7.1]
  PERMISSIONS = %w[
    conversations.import
  ].freeze

  ROLE_KEYS = %w[super_admin account_owner agent].freeze

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
