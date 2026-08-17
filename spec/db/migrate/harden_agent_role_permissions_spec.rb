# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260817120001_harden_agent_role_permissions.rb')

# Spec for the agent-role RBAC hardening data-migration (cards #178/#181/#182).
# On upgrade it reconciles the EXISTING system `agent` role to the trimmed seed:
# it revokes conversations.read_all + the destructive/admin keys, and grants the
# new dedicated pipeline_items.update. Custom roles and the operational chat
# permissions must be left intact.
RSpec.describe HardenAgentRolePermissions do
  let(:migration) { described_class.new }

  before { migration.singleton_class.send(:public, :up, :down) }
  before { load Rails.root.join('db/seeds/rbac.rb') }

  def keys(role)
    role.reload.role_permissions_actions.pluck(:permission_key)
  end

  # Simulate a pre-fix (already-bootstrapped) install: the old seed granted the
  # now-revoked keys to the agent and did NOT grant pipeline_items.update.
  def to_pre_fix_state(role)
    HardenAgentRolePermissions::REVOKED_PERMISSIONS.each do |pk|
      record = role.role_permissions_actions.find_or_initialize_by(permission_key: pk)
      record.save!(validate: false) if record.new_record?
    end
    role.role_permissions_actions
        .where(permission_key: HardenAgentRolePermissions::GRANTED_PERMISSIONS)
        .destroy_all
  end

  describe '#up' do
    it 'revokes read_all and the destructive/admin keys from the system agent role' do
      agent = Role.find_by!(key: 'agent')
      to_pre_fix_state(agent)

      migration.up

      expect(keys(agent)).not_to include(
        'conversations.read_all', 'conversations.delete', 'contacts.delete',
        'pipeline_stages.delete', 'teams.create', 'teams.update', 'teams.delete'
      )
    end

    it 'grants the dedicated pipeline_items.update card-write key' do
      agent = Role.find_by!(key: 'agent')
      to_pre_fix_state(agent)

      migration.up

      expect(keys(agent)).to include('pipeline_items.update')
    end

    it 'keeps the operational permissions attendance depends on' do
      agent = Role.find_by!(key: 'agent')
      to_pre_fix_state(agent)

      migration.up

      expect(keys(agent)).to include(
        'conversations.read', 'conversations.create', 'conversations.update',
        'conversations.toggle_status', 'contacts.read', 'contacts.create',
        'labels.read', 'macros.execute', 'teams.read',
        'pipeline_stages.read', 'pipeline_stages.create', 'pipeline_stages.update'
      )
    end

    it 'does not touch a custom (non-system) role that holds the same keys' do
      custom = Role.create!(key: "manager-#{SecureRandom.hex(4)}", name: 'Manager', type: 'account', system: false)
      custom.role_permissions_actions.create!(permission_key: 'conversations.read_all')
      custom.role_permissions_actions.create!(permission_key: 'teams.delete')

      migration.up

      expect(keys(custom)).to include('conversations.read_all', 'teams.delete')
    end

    it 'is idempotent' do
      agent = Role.find_by!(key: 'agent')
      to_pre_fix_state(agent)

      expect do
        migration.up
        migration.up
      end.not_to raise_error
      expect(keys(agent)).not_to include('conversations.read_all')
      expect(keys(agent)).to include('pipeline_items.update')
    end
  end

  describe '#down' do
    it 'best-effort re-grants the revoked keys and removes the granted one' do
      agent = Role.find_by!(key: 'agent')
      migration.up

      migration.down

      expect(keys(agent)).to include('conversations.read_all', 'teams.delete')
      expect(keys(agent)).not_to include('pipeline_items.update')
    end
  end
end
