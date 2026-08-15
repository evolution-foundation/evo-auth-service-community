# frozen_string_literal: true

# Backfills the `ai_integration_credentials.*` and `ai_api_keys.*` permission keys
# to already-bootstrapped installations.
#
# `ai_integration_credentials` entered ResourceActionsConfig with no data
# migration. Deploys that run `db:seed` on boot regrant the admin roles from the
# full catalog and pick it up; installs that only run `migrate` do not, and the
# "Integration Credentials" screen ships dark for every role, super_admin
# included. `ai_api_keys` is granted by the seed already and is included as an
# idempotent safety net so both AI credential screens stay paired.
#
# Pattern mirrors AddProductPermissionsToExistingRoles (20260513163200): the same
# SELECT-before-INSERT idempotency, no-op when the role does not exist yet.
class AddAiCredentialsPermissionsToExistingRoles < ActiveRecord::Migration[7.1]
  PERMISSIONS = %w[
    ai_integration_credentials.read
    ai_integration_credentials.create
    ai_integration_credentials.update
    ai_integration_credentials.delete
    ai_api_keys.read
    ai_api_keys.create
    ai_api_keys.update
    ai_api_keys.delete
  ].freeze

  # `agent` is intentionally omitted: administrative Settings resources (AI
  # agents/keys/credentials) are withheld from the default agent role on purpose
  # (see the EVO-1938 note in db/seeds/rbac.rb); grant per role via the editor.
  ROLE_KEYS = %w[super_admin account_owner].freeze

  def up
    # Fresh installs hit this migration before init_schema (timestamp 9025…)
    # has run, so `roles` may not exist yet — seed will cover it later.
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
