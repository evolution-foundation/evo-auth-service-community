# frozen_string_literal: true

# Backfills the B14 (lead-capture) permissions added in ResourceActionsConfig
# (crm_forms.* and chat_pages.*) to already-bootstrapped installations.
#
# New installations pick these up automatically via db/seeds/rbac.rb when
# SetupBootstrapService runs; existing installations skip the seed after
# bootstrap, and releases run `migrate` (not `seed`). Without this data
# migration the admin CRUD endpoints (/api/v1/crm_forms, /api/v1/chat_pages)
# 403 for everyone — including super_admin, whose access is grant-backed, not
# bypassed — until someone runs the seed in prod. So B14 would ship dark.
#
# Pattern mirrors AddProductPermissionsToExistingRoles (20260513163200) — same
# idempotency guarantees (SELECT-before-INSERT, no-op when the role is absent).
class AddCrmFormsAndChatPagesPermissionsToExistingRoles < ActiveRecord::Migration[7.1]
  PERMISSIONS = %w[
    crm_forms.read
    crm_forms.create
    crm_forms.update
    crm_forms.delete
    chat_pages.read
    chat_pages.create
    chat_pages.update
    chat_pages.delete
  ].freeze

  # Roles that should automatically receive the full set on upgrade. `agent` is
  # intentionally omitted (mirrors the products backfill) — granted manually via
  # the role editor when an operator should manage the catalog.
  ROLE_KEYS = %w[super_admin account_owner].freeze

  def up
    # Fresh installs hit this migration before init_schema has run, so `roles`
    # may not exist yet — the seed covers them later.
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
