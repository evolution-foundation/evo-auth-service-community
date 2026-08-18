# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260817120009_grant_pipeline_items_update_to_agent.rb')

# Spec for the CRM-178 data-migration. On upgrade it grants the dedicated
# pipeline_items.update card-write key to the EXISTING system `agent` role,
# without touching custom roles or the operational chat permissions.
RSpec.describe GrantPipelineItemsUpdateToAgent do
  let(:migration) { described_class.new }

  before { load Rails.root.join('db/seeds/rbac.rb') }

  def keys(role)
    role.reload.role_permissions_actions.pluck(:permission_key)
  end

  # Simulate a pre-fix install: the old seed did NOT grant pipeline_items.update.
  def to_pre_fix_state(role)
    role.role_permissions_actions
        .where(permission_key: described_class::GRANTED_PERMISSIONS)
        .destroy_all
  end

  describe '#up' do
    it 'grants pipeline_items.update to the system agent role' do
      agent = Role.find_by!(key: 'agent')
      to_pre_fix_state(agent)

      migration.up

      expect(keys(agent)).to include('pipeline_items.update')
    end

    it 'does not touch a custom (non-system) role' do
      custom = Role.create!(key: "manager-#{SecureRandom.hex(4)}", name: 'Manager', type: 'account', system: false)

      migration.up

      expect(keys(custom)).not_to include('pipeline_items.update')
    end

    it 'is idempotent' do
      agent = Role.find_by!(key: 'agent')
      to_pre_fix_state(agent)

      expect do
        migration.up
        migration.up
      end.not_to raise_error
      expect(keys(agent).count { |k| k == 'pipeline_items.update' }).to eq(1)
    end

    it 'is a no-op when the agent role is absent' do
      Role.where(key: 'agent').destroy_all

      expect { migration.up }.not_to raise_error
    end
  end

  describe '#down' do
    it 'removes the grant it created (clean reverse of an additive migration)' do
      agent = Role.find_by!(key: 'agent')
      migration.up
      expect(keys(agent)).to include('pipeline_items.update')

      migration.down

      expect(keys(agent)).not_to include('pipeline_items.update')
    end
  end
end
