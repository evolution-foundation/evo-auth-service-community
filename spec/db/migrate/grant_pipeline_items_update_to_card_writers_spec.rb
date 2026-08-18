# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260817120009_grant_pipeline_items_update_to_card_writers.rb')

# Spec for the CRM-178 data-migration. On upgrade it grants the dedicated
# pipeline_items.update card-write key to the system `agent` role AND to every role
# that already holds pipelines.update — those can write cards today, and the gate
# split would take it away from them silently.
RSpec.describe GrantPipelineItemsUpdateToCardWriters do
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

  def custom_role(*permission_keys)
    suffix = SecureRandom.hex(4)
    role = Role.create!(key: "manager-#{suffix}", name: "Manager #{suffix}", type: 'account', system: false)
    permission_keys.each { |key| role.role_permissions_actions.create!(permission_key: key) }
    role
  end

  describe '#up' do
    it 'grants pipeline_items.update to the system agent role' do
      agent = Role.find_by!(key: 'agent')
      to_pre_fix_state(agent)

      migration.up

      expect(keys(agent)).to include('pipeline_items.update')
    end

    # The regression the migration exists to prevent: a per-client role built to work
    # the funnel holds pipelines.update — the ONLY key that unlocked card writes before
    # this card. Without the backfill it starts taking 401 on every card move.
    it 'grants the key to a CUSTOM role that already holds pipelines.update' do
      custom = custom_role('pipelines.read', 'pipelines.update')

      migration.up

      expect(keys(custom)).to include('pipeline_items.update')
    end

    it 'does not touch a custom role that cannot write cards today' do
      custom = custom_role('pipelines.read')

      migration.up

      expect(keys(custom)).not_to include('pipeline_items.update')
    end

    it 'does not touch a custom role with no permissions at all' do
      custom = custom_role

      migration.up

      expect(keys(custom)).not_to include('pipeline_items.update')
    end

    it 'is idempotent' do
      agent = Role.find_by!(key: 'agent')
      custom = custom_role('pipelines.update')
      to_pre_fix_state(agent)

      expect do
        migration.up
        migration.up
      end.not_to raise_error
      expect(keys(agent).count { |k| k == 'pipeline_items.update' }).to eq(1)
      expect(keys(custom).count { |k| k == 'pipeline_items.update' }).to eq(1)
    end

    it 'is a no-op when the agent role is absent' do
      Role.where(key: 'agent').destroy_all

      expect { migration.up }.not_to raise_error
    end
  end

  describe '#down' do
    it 'removes the grant it created (clean reverse of an additive migration)' do
      agent = Role.find_by!(key: 'agent')
      custom = custom_role('pipelines.update')
      migration.up
      expect(keys(agent)).to include('pipeline_items.update')
      expect(keys(custom)).to include('pipeline_items.update')

      migration.down

      expect(keys(agent)).not_to include('pipeline_items.update')
      expect(keys(custom)).not_to include('pipeline_items.update')
    end
  end
end
