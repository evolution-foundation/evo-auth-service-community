# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260817120005_revoke_destructive_keys_from_agent.rb')

# Spec for the CRM-182 data-migration (least-privilege for the attendance role).
# On upgrade it revokes the destructive/admin keys from the EXISTING system
# `agent` role. Custom roles and the operational chat permissions stay intact,
# and the rollback must NOT re-grant the keys (that would be a privilege escalation).
RSpec.describe RevokeDestructiveKeysFromAgent do
  let(:migration) { described_class.new }

  before { load Rails.root.join('db/seeds/rbac.rb') }

  def keys(role)
    role.reload.role_permissions_actions.pluck(:permission_key)
  end

  # Simulate a pre-fix (already-bootstrapped) install: the old seed granted the
  # now-revoked keys to the agent.
  def to_pre_fix_state(role)
    described_class::REVOKED_PERMISSIONS.each do |pk|
      next if role.role_permissions_actions.exists?(permission_key: pk)

      role.role_permissions_actions.create!(permission_key: pk)
    end
  end

  describe '#up' do
    it 'revokes the destructive/admin keys from the system agent role' do
      agent = Role.find_by!(key: 'agent')
      to_pre_fix_state(agent)

      migration.up

      expect(keys(agent)).not_to include(
        'conversations.delete', 'contacts.delete', 'pipeline_stages.delete',
        'teams.create', 'teams.update', 'teams.delete'
      )
    end

    it 'keeps the operational permissions attendance depends on' do
      agent = Role.find_by!(key: 'agent')
      to_pre_fix_state(agent)

      migration.up

      expect(keys(agent)).to include(
        'conversations.read', 'conversations.create', 'conversations.update',
        'conversations.toggle_status', 'contacts.read', 'contacts.create',
        'teams.read', 'pipeline_stages.read', 'pipeline_stages.create', 'pipeline_stages.update'
      )
    end

    it 'does not touch a custom (non-system) role that holds the same keys' do
      custom = Role.create!(key: "manager-#{SecureRandom.hex(4)}", name: 'Manager', type: 'account', system: false)
      custom.role_permissions_actions.create!(permission_key: 'conversations.delete')
      custom.role_permissions_actions.create!(permission_key: 'teams.delete')

      migration.up

      expect(keys(custom)).to include('conversations.delete', 'teams.delete')
    end

    it 'is idempotent' do
      agent = Role.find_by!(key: 'agent')
      to_pre_fix_state(agent)

      expect do
        migration.up
        migration.up
      end.not_to raise_error
      expect(keys(agent)).not_to include('teams.delete')
    end

    it 'is a no-op when the agent role is absent' do
      Role.where(key: 'agent').destroy_all

      expect { migration.up }.not_to raise_error
    end
  end

  describe '#down' do
    it 'does NOT re-grant the revoked keys (forward-only; re-granting would escalate privilege)' do
      agent = Role.find_by!(key: 'agent')
      to_pre_fix_state(agent)
      migration.up
      expect(keys(agent)).not_to include('teams.delete')

      migration.down

      expect(keys(agent)).not_to include(
        'conversations.delete', 'contacts.delete', 'pipeline_stages.delete',
        'teams.create', 'teams.update', 'teams.delete'
      )
    end
  end
end
