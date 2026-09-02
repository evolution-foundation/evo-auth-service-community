# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260817120007_revoke_shared_asset_deletes_from_agent.rb')

# Spec for the CRM-190 data-migration (attendance role must not delete shared
# account assets). On upgrade it revokes labels/macros/canned_responses/
# message_templates .delete from the EXISTING system `agent` role. Custom roles
# and the operational read/create/update + macros.execute stay intact, and the
# rollback must NOT re-grant the keys (that would be a privilege escalation).
RSpec.describe RevokeSharedAssetDeletesFromAgent do
  let(:migration) { described_class.new }

  before { load Rails.root.join('db/seeds/rbac.rb') }

  def keys(role)
    role.reload.role_permissions_actions.pluck(:permission_key)
  end

  # Simulate a pre-fix install: the old seed granted the now-revoked keys.
  def to_pre_fix_state(role)
    described_class::REVOKED_PERMISSIONS.each do |pk|
      next if role.role_permissions_actions.exists?(permission_key: pk)

      role.role_permissions_actions.create!(permission_key: pk)
    end
  end

  describe '#up' do
    it 'revokes the shared-asset delete keys from the system agent role' do
      agent = Role.find_by!(key: 'agent')
      to_pre_fix_state(agent)

      migration.up

      expect(keys(agent)).not_to include(
        'labels.delete', 'macros.delete', 'canned_responses.delete', 'message_templates.delete'
      )
    end

    it 'keeps the operational keys of each asset (this migration only revokes deletes)' do
      agent = Role.find_by!(key: 'agent')
      to_pre_fix_state(agent)

      migration.up

      # macros/message_templates create+update left the seed with CRM-70; what
      # the seed still grants must survive this migration untouched.
      expect(keys(agent)).to include(
        'labels.read', 'labels.create', 'labels.update',
        'canned_responses.read', 'canned_responses.create', 'canned_responses.update',
        'message_templates.read',
        'macros.read', 'macros.execute'
      )
    end

    it 'does not touch a custom (non-system) role that holds the same keys' do
      custom = Role.create!(key: "manager-#{SecureRandom.hex(4)}", name: 'Manager', type: 'account', system: false)
      custom.role_permissions_actions.create!(permission_key: 'labels.delete')
      custom.role_permissions_actions.create!(permission_key: 'macros.delete')

      migration.up

      expect(keys(custom)).to include('labels.delete', 'macros.delete')
    end

    it 'is idempotent' do
      agent = Role.find_by!(key: 'agent')
      to_pre_fix_state(agent)

      expect do
        migration.up
        migration.up
      end.not_to raise_error
      expect(keys(agent)).not_to include('labels.delete')
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
      expect(keys(agent)).not_to include('macros.delete')

      migration.down

      expect(keys(agent)).not_to include(
        'labels.delete', 'macros.delete', 'canned_responses.delete', 'message_templates.delete'
      )
    end
  end
end
