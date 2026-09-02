# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260818120003_revoke_manage_writes_from_agent.rb')

# Spec for the CRM-70 data-migration (use-vs-manage split). On upgrade it revokes
# macros/message_templates create+update from the EXISTING system `agent` role,
# keeping what the chat needs (read, macros.execute). Custom roles stay intact
# and the rollback must NOT re-grant (privilege escalation).
RSpec.describe RevokeManageWritesFromAgent do
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
    it 'revokes macros/message_templates create and update from the system agent role' do
      agent = Role.find_by!(key: 'agent')
      to_pre_fix_state(agent)

      migration.up

      expect(keys(agent)).not_to include(
        'macros.create', 'macros.update', 'message_templates.create', 'message_templates.update'
      )
    end

    it 'keeps what the chat needs: read of both, macros.execute, and the labels/canned writes' do
      agent = Role.find_by!(key: 'agent')
      to_pre_fix_state(agent)

      migration.up

      expect(keys(agent)).to include(
        'macros.read', 'macros.execute', 'message_templates.read',
        'labels.create', 'labels.update', 'canned_responses.create', 'canned_responses.update'
      )
    end

    it 'does not touch a custom (non-system) role that holds the same keys' do
      custom = Role.create!(key: "manager-#{SecureRandom.hex(4)}", name: 'Manager', type: 'account', system: false)
      custom.role_permissions_actions.create!(permission_key: 'macros.create')
      custom.role_permissions_actions.create!(permission_key: 'message_templates.update')

      migration.up

      expect(keys(custom)).to include('macros.create', 'message_templates.update')
    end

    it 'leaves the admin roles untouched' do
      migration.up

      expect(keys(Role.find_by!(key: 'account_owner'))).to include('macros.create', 'message_templates.update')
    end

    it 'is idempotent' do
      agent = Role.find_by!(key: 'agent')
      to_pre_fix_state(agent)

      expect do
        migration.up
        migration.up
      end.not_to raise_error
      expect(keys(agent)).not_to include('macros.create')
    end

    it 'is a no-op when the agent role is absent' do
      Role.where(key: 'agent').destroy_all

      expect { migration.up }.not_to raise_error
    end
  end

  describe '#down' do
    it 'does NOT re-grant (forward-only; re-granting would escalate privilege)' do
      agent = Role.find_by!(key: 'agent')
      to_pre_fix_state(agent)
      migration.up

      migration.down

      expect(keys(agent)).not_to include('macros.create', 'message_templates.create')
    end
  end
end
