# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260817120003_revoke_read_all_from_agent.rb')

# Spec for the CRM-181 data-migration (secure-by-default inbox visibility).
# On upgrade it revokes conversations.read_all from the EXISTING system `agent`
# role. Custom roles and the operational chat permissions stay intact, and the
# rollback must NOT re-grant the key (that would be a privilege escalation).
RSpec.describe RevokeReadAllFromAgent do
  let(:migration) { described_class.new }

  before { load Rails.root.join('db/seeds/rbac.rb') }

  def keys(role)
    role.reload.role_permissions_actions.pluck(:permission_key)
  end

  # Simulate a pre-fix (already-bootstrapped) install: the old seed granted
  # conversations.read_all to the agent.
  def to_pre_fix_state(role)
    described_class::REVOKED_PERMISSIONS.each do |pk|
      next if role.role_permissions_actions.exists?(permission_key: pk)

      role.role_permissions_actions.create!(permission_key: pk)
    end
  end

  describe '#up' do
    it 'revokes conversations.read_all from the system agent role' do
      agent = Role.find_by!(key: 'agent')
      to_pre_fix_state(agent)

      migration.up

      expect(keys(agent)).not_to include('conversations.read_all')
    end

    it 'keeps the operational permissions attendance depends on' do
      agent = Role.find_by!(key: 'agent')
      to_pre_fix_state(agent)

      migration.up

      expect(keys(agent)).to include(
        'conversations.read', 'conversations.create', 'conversations.update',
        'conversations.toggle_status', 'contacts.read', 'inboxes.read', 'users.read'
      )
    end

    it 'does not touch a custom (non-system) role that holds read_all' do
      custom = Role.create!(key: "manager-#{SecureRandom.hex(4)}", name: 'Manager', type: 'account', system: false)
      custom.role_permissions_actions.create!(permission_key: 'conversations.read_all')

      migration.up

      expect(keys(custom)).to include('conversations.read_all')
    end

    it 'leaves account_owner and super_admin read_all intact' do
      migration.up

      expect(keys(Role.find_by!(key: 'account_owner'))).to include('conversations.read_all')
      expect(keys(Role.find_by!(key: 'super_admin'))).to include('conversations.read_all')
    end

    it 'is idempotent' do
      agent = Role.find_by!(key: 'agent')
      to_pre_fix_state(agent)

      expect do
        migration.up
        migration.up
      end.not_to raise_error
      expect(keys(agent)).not_to include('conversations.read_all')
    end

    it 'does not raise while counting agents without inbox membership' do
      # inbox_members is a CRM table; the count is guarded/rescued, so `up`
      # must succeed whether or not the table exists in this schema.
      agent = Role.find_by!(key: 'agent')
      to_pre_fix_state(agent)

      expect { migration.up }.not_to raise_error
    end

    it 'is a no-op when the agent role is absent' do
      Role.where(key: 'agent').destroy_all

      expect { migration.up }.not_to raise_error
    end
  end

  describe '#down' do
    it 'does NOT re-grant read_all (forward-only; re-granting would escalate privilege)' do
      agent = Role.find_by!(key: 'agent')
      to_pre_fix_state(agent)
      migration.up
      expect(keys(agent)).not_to include('conversations.read_all')

      migration.down

      expect(keys(agent)).not_to include('conversations.read_all')
    end
  end
end
