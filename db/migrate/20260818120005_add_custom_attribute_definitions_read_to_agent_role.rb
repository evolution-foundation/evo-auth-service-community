# frozen_string_literal: true

# Backfills `custom_attribute_definitions.read` to the `agent` role (CRM-166).
#
# The role already WRITES custom attribute values but held no read on the
# DEFINITIONS, which Api::V1::CustomAttributeDefinitionsController#index gates on,
# so the CRM rendered the 403 as "no custom attributes". Fresh installs pick the key
# up from db/seeds/rbac.rb; already-bootstrapped ones run `db:migrate` without
# `db:seed`, so they need this data migration.
class AddCustomAttributeDefinitionsReadToAgentRole < ActiveRecord::Migration[7.1]
  PERMISSION_KEY = 'custom_attribute_definitions.read'

  def up
    # No-op on a database that is not bootstrapped yet — the seed covers it there.
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
