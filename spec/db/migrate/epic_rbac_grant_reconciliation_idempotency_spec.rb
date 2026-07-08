# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260707150000_revoke_accounts_update_from_agent_role.rb')
require Rails.root.join('db/migrate/20260707170000_grant_integrations_execute_to_admin_roles.rb')

# The paired data-migrations that trim the RBAC grant set on already-bootstrapped
# installations. Fresh installs pick up the trimmed catalog/seed; existing
# installations skip the seed, so the risk lives entirely in `up` running
# against a database that STILL HOLDS the old grant. These examples seed the
# legacy grant first and assert the migrations converge on the trimmed set
# without erroring or duplicating.
RSpec.describe 'Epic RBAC grant reconciliation idempotency' do
  # Seed the system roles (account_owner / super_admin / agent) so the
  # migrations have their target rows.
  before { load Rails.root.join('db/seeds/rbac.rb') }

  def keys(role)
    role.reload.role_permissions_actions.pluck(:permission_key)
  end

  describe RevokeAccountsUpdateFromAgentRole do
    let(:migration) { described_class.new }
    let(:agent) { Role.find_by!(key: 'agent') }

    before do
      # Simulate the legacy state: an already-bootstrapped agent role that still
      # carries the administrative accounts.update grant the old seed handed out.
      agent.role_permissions_actions.create!(permission_key: 'accounts.update') \
        unless agent.role_permissions_actions.exists?(permission_key: 'accounts.update')
    end

    it 'strips the legacy accounts.update grant while keeping accounts.read' do
      expect(keys(agent)).to include('accounts.update')

      migration.up

      expect(keys(agent)).not_to include('accounts.update')
      expect(keys(agent)).to include('accounts.read')
    end

    it 'is idempotent — re-running up over the already-trimmed role is a safe no-op' do
      migration.up
      expect { migration.up }.not_to raise_error

      expect(keys(agent)).not_to include('accounts.update')
    end
  end

  describe GrantIntegrationsExecuteToAdminRoles do
    let(:migration) { described_class.new }
    let(:account_owner) { Role.find_by!(key: 'account_owner') }
    let(:super_admin) { Role.find_by!(key: 'super_admin') }
    let(:agent) { Role.find_by!(key: 'agent') }

    it 'grants integrations.execute to the admin system roles' do
      # Reset to the pre-grant state so the assertion exercises the migration.
      [account_owner, super_admin].each do |role|
        role.role_permissions_actions.where(permission_key: 'integrations.execute').destroy_all
      end

      migration.up

      expect(keys(account_owner)).to include('integrations.execute')
      expect(keys(super_admin)).to include('integrations.execute')
    end

    it 'does not duplicate the grant when the DB already holds it (legacy state)' do
      # Simulate an install that already carries the grant (fresh seed OR a prior
      # run). The migration's exists?-before-create guard must not create a second
      # row (the unique index would otherwise raise).
      account_owner.role_permissions_actions.create!(permission_key: 'integrations.execute') \
        unless account_owner.role_permissions_actions.exists?(permission_key: 'integrations.execute')

      expect { migration.up }.not_to raise_error

      expect(keys(account_owner).count('integrations.execute')).to eq(1)
    end

    it 'does NOT grant integrations.execute to the default agent role' do
      agent.role_permissions_actions.where(permission_key: 'integrations.execute').destroy_all

      migration.up

      expect(keys(agent)).not_to include('integrations.execute')
    end
  end

  describe 'seed reconciliation — phantom keys are pruned' do
    let(:account_owner) { Role.find_by!(key: 'account_owner') }

    it 'drops grants for keys no longer present in the catalog' do
      # Inject a grant for a key the catalog no longer defines (bypassing the
      # model validation, exactly as a stale row from a removed enterprise
      # resource would have survived an upgrade).
      phantom = RolePermissionsAction.new(role: account_owner, permission_key: 'plans.read')
      phantom.save!(validate: false)
      expect(keys(account_owner)).to include('plans.read')
      expect(ResourceActionsConfig.valid_permission?('plans.read')).to be(false)

      # Re-running the seed reconciles the grant set against the current catalog.
      load Rails.root.join('db/seeds/rbac.rb')

      expect(keys(account_owner)).not_to include('plans.read')
    end
  end
end
