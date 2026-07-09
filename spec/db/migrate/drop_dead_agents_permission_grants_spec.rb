# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260709120000_drop_dead_agents_permission_grants.rb')

# EVO-2072 — the dead twin `agents` left the catalog, so its stored grants must go.
# They must be DELETED, never rewritten into `ai_agents.*`: `agents.*` on its own
# granted nothing (evo-core gates /agents with `ai_agents.*`, and the CRM proxy
# forwards the caller's token), so promoting it would hand real AI-agent management
# to roles that never had it — the privilege escalation NFR1 forbids.
RSpec.describe DropDeadAgentsPermissionGrants do
  let(:migration) { described_class.new }

  before { migration.singleton_class.send(:public, :up, :down) }

  def make_role
    suffix = SecureRandom.hex(4)
    Role.create!(key: "role-#{suffix}", name: "Role #{suffix}", type: 'account', system: false)
  end

  # Persist a grant bypassing catalog validation — `agents.*` is exactly the kind
  # of now-invalid key this migration exists to clean up.
  def grant_raw(role, permission_key)
    role.role_permissions_actions.build(permission_key: permission_key).save!(validate: false)
  end

  def keys(role)
    role.reload.role_permissions_actions.pluck(:permission_key)
  end

  describe '#up' do
    it 'deletes every dead agents.* grant' do
      role = make_role
      %w[agents.read agents.create agents.update agents.delete].each { |k| grant_raw(role, k) }

      migration.up

      expect(keys(role)).to be_empty
    end

    # The NFR1 invariant. A role that only ever held the inert `agents.*` must not
    # come out of this migration holding live `ai_agents.*` capability.
    it 'does NOT promote agents.* into ai_agents.* (no privilege escalation)' do
      role = make_role
      %w[agents.read agents.delete].each { |k| grant_raw(role, k) }

      migration.up

      expect(keys(role)).to be_empty
      expect(keys(role)).not_to include('ai_agents.read', 'ai_agents.delete')
    end

    it 'leaves a genuine ai_agents.* grant untouched' do
      role = make_role
      grant_raw(role, 'agents.read')
      grant_raw(role, 'ai_agents.read')
      grant_raw(role, 'conversations.read')

      migration.up

      expect(keys(role)).to contain_exactly('ai_agents.read', 'conversations.read')
    end

    # `agents.` must not swallow the look-alike resources that survive.
    it 'does not touch look-alike resources' do
      role = make_role
      %w[ai_agents.sync agent_bots.read].each { |k| grant_raw(role, k) }

      migration.up

      expect(keys(role)).to contain_exactly('ai_agents.sync', 'agent_bots.read')
    end

    it 'is idempotent' do
      role = make_role
      grant_raw(role, 'agents.create')
      grant_raw(role, 'ai_agents.create')

      expect do
        migration.up
        migration.up
      end.not_to raise_error

      expect(keys(role)).to contain_exactly('ai_agents.create')
    end
  end

  describe 'system roles (seeded) keep every capability' do
    before { load Rails.root.join('db/seeds/rbac.rb') }

    it 'leaves super_admin holding exactly the catalog keys' do
      migration.up

      super_admin = Role.find_by!(key: 'super_admin')
      expect(keys(super_admin)).to match_array(ResourceActionsConfig.all_permission_keys)
    end

    it 'leaves account_owner with ai_agents intact and no stale agents.* keys' do
      migration.up

      account_owner = Role.find_by!(key: 'account_owner')
      expect(keys(account_owner)).to include(
        'ai_agents.read', 'ai_agents.create', 'ai_agents.update', 'ai_agents.delete'
      )
      expect(keys(account_owner).grep(/\Aagents\./)).to be_empty
    end

    # EVO-1938 revoked the administrative Settings resources from the attendant
    # role; dropping `agents` must not hand AI-agent management back to it.
    it 'does not grant the agent role any ai_agents capability' do
      migration.up

      agent = Role.find_by!(key: 'agent')
      expect(keys(agent).grep(/\Aai_agents\./)).to be_empty
    end
  end

  describe '#down' do
    it 'is a non-reversible no-op' do
      role = make_role
      grant_raw(role, 'ai_agents.read')

      expect { migration.down }.not_to raise_error
      expect(keys(role)).to contain_exactly('ai_agents.read')
    end
  end
end
