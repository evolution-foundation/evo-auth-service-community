# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260709120000_consolidate_agents_permissions_into_ai_agents.rb')

# Spec for the EVO-2072 data-migration that consolidates the dead twin `agents.*`
# grants into `ai_agents.*`. On an already-bootstrapped install,
# role_permissions_actions still carries `agents.*` rows (the catalog no longer
# defines that resource). The migration must grant the equivalent `ai_agents.*`
# capability, drop the dead `agents.*` rows WITHOUT tripping the unique index
# (role_id, permission_key), and leave every surviving capability — and the
# system roles — intact.
RSpec.describe ConsolidateAgentsPermissionsIntoAiAgents do
  let(:migration) { described_class.new }

  before { migration.singleton_class.send(:public, :up, :down) }

  def make_role
    suffix = SecureRandom.hex(4)
    Role.create!(key: "role-#{suffix}", name: "Role #{suffix}", type: 'account', system: false)
  end

  # Persist a grant bypassing the catalog validation — `agents.*` is no longer a
  # valid catalog key, which is precisely why the migration exists.
  def grant_raw(role, permission_key)
    record = role.role_permissions_actions.build(permission_key: permission_key)
    record.save!(validate: false)
  end

  def keys(role)
    role.reload.role_permissions_actions.pluck(:permission_key)
  end

  describe '#up' do
    it 'rewrites a lone agents.<action> to ai_agents.<action> in place' do
      role = make_role
      grant_raw(role, 'agents.read')

      migration.up

      expect(keys(role)).to contain_exactly('ai_agents.read')
    end

    it 'consolidates all four agents actions onto ai_agents.*' do
      role = make_role
      %w[agents.read agents.create agents.update agents.delete].each { |k| grant_raw(role, k) }

      migration.up

      expect(keys(role)).to contain_exactly(
        'ai_agents.read', 'ai_agents.create', 'ai_agents.update', 'ai_agents.delete'
      )
    end

    it 'dedups when the ai_agents target already exists (unique-index-safe)' do
      role = make_role
      grant_raw(role, 'ai_agents.read')
      grant_raw(role, 'agents.read')

      expect { migration.up }.not_to raise_error

      expect(keys(role)).to contain_exactly('ai_agents.read')
    end

    it 'leaves unrelated grants untouched' do
      role = make_role
      grant_raw(role, 'agents.read')
      grant_raw(role, 'conversations.read')
      grant_raw(role, 'ai_agents.sync')

      migration.up

      expect(keys(role)).to contain_exactly('ai_agents.read', 'conversations.read', 'ai_agents.sync')
    end

    it 'is idempotent' do
      role = make_role
      grant_raw(role, 'agents.create')

      expect do
        migration.up
        migration.up
      end.not_to raise_error

      expect(keys(role)).to contain_exactly('ai_agents.create')
    end
  end

  describe 'system roles (seeded) keep every capability' do
    before { load Rails.root.join('db/seeds/rbac.rb') }

    it 'leaves super_admin holding all catalog keys after the migration' do
      migration.up

      super_admin = Role.find_by!(key: 'super_admin')
      expect(keys(super_admin)).to match_array(ResourceActionsConfig.all_permission_keys)
      expect(keys(super_admin)).not_to include('agents.read', 'agents.create', 'agents.update', 'agents.delete')
    end

    it 'leaves account_owner holding the ai_agents capability and no stale agents.* keys' do
      migration.up

      account_owner = Role.find_by!(key: 'account_owner')
      expect(keys(account_owner)).to include('ai_agents.read', 'ai_agents.create', 'ai_agents.update', 'ai_agents.delete')
      expect(keys(account_owner).grep(/\Aagents\./)).to be_empty
    end
  end

  describe '#down' do
    it 'is non-reversible' do
      expect { migration.down }.to raise_error(ActiveRecord::IrreversibleMigration)
    end
  end
end
