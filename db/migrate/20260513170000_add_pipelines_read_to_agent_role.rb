# frozen_string_literal: true

# Backfills `pipelines.read` to the `agent` role on already-bootstrapped
# installations.
#
# New installations pick this up automatically via db/seeds/rbac.rb when
# SetupBootstrapService runs; existing installations skip the seed after
# bootstrap (production deploys run `bin/rails db:migrate`, not
# `bin/rails db:seed`), so they need a data migration to receive the
# permission.
#
# See db/migrate/20260505155854_promote_first_user_to_super_admin.rb for the
# established team convention: changes to db/seeds/rbac.rb that affect an
# already-existing role must ship alongside an idempotent migration so
# operators do not have to run seeds manually post-deploy.
#
# Idempotent: SELECT-before-INSERT, no-op if role missing (e.g. not yet
# bootstrapped — the seed will handle it on first install).
class AddPipelinesReadToAgentRole < ActiveRecord::Migration[7.1]
  PERMISSION_KEY = 'pipelines.read'

  def up
    # Fresh installs hit this migration before init_schema (timestamp 9025…)
    # has run, so `roles` may not exist yet — seed will cover it later.
    return unless ActiveRecord::Base.connection.table_exists?(:roles)
    return unless ActiveRecord::Base.connection.table_exists?(:role_permissions_actions)

    role = Role.find_by(key: 'agent')
    return unless role # bootstrapped install without agent role — seed will cover it

    return if role.role_permissions_actions.exists?(permission_key: PERMISSION_KEY)

    role.role_permissions_actions.create!(permission_key: PERMISSION_KEY)
  end

  def down
    return unless ActiveRecord::Base.connection.table_exists?(:roles)

    role = Role.find_by(key: 'agent')
    return unless role

    role.role_permissions_actions.where(permission_key: PERMISSION_KEY).destroy_all
  end
end
