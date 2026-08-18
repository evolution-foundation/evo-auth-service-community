# frozen_string_literal: true

# Backfills `custom_attribute_definitions.read` to the `agent` role on
# already-bootstrapped installations (CRM-166).
#
# The agent role already WRITES custom attribute values
# (conversations.custom_attributes, contacts.destroy_custom_attributes) but never
# received the read on the DEFINITIONS, which is what
# Api::V1::CustomAttributeDefinitionsController#index gates on in the CRM. The
# 403 surfaced in the UI as "no custom attributes", so a contact's attributes were
# only visible inside the edit form (which falls back to rendering raw keys).
#
# New installations pick this up from db/seeds/rbac.rb; existing ones run
# `db:migrate` and not `db:seed`, so they need this data migration.
#
# Idempotent: SELECT-before-INSERT, no-op if the role is missing (not yet
# bootstrapped — the seed covers it on first install).
class AddCustomAttributeDefinitionsReadToAgentRole < ActiveRecord::Migration[7.1]
  PERMISSION_KEY = 'custom_attribute_definitions.read'

  def up
    # Fresh installs hit this migration before init_schema (timestamp 9025…)
    # has run, so `roles` may not exist yet — seed will cover it later.
    return unless ActiveRecord::Base.connection.table_exists?(:roles)
    return unless ActiveRecord::Base.connection.table_exists?(:role_permissions_actions)

    role = Role.find_by(key: 'agent')
    return unless role

    return if role.role_permissions_actions.exists?(permission_key: PERMISSION_KEY)

    role.role_permissions_actions.create!(permission_key: PERMISSION_KEY)
  end

  def down
    return unless ActiveRecord::Base.connection.table_exists?(:roles)
    return unless ActiveRecord::Base.connection.table_exists?(:role_permissions_actions)

    role = Role.find_by(key: 'agent')
    return unless role

    role.role_permissions_actions.where(permission_key: PERMISSION_KEY).destroy_all
  end
end
