# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260818120005_add_custom_attribute_definitions_read_to_agent_role.rb')

# CRM-166. Pins the backfill for already-bootstrapped installations, which run
# `db:migrate` and never re-run the seed.
RSpec.describe AddCustomAttributeDefinitionsReadToAgentRole do
  let(:migration) { described_class.new }
  let(:key) { described_class::PERMISSION_KEY }

  before { load Rails.root.join('db/seeds/rbac.rb') }

  def keys(role_key)
    Role.find_by!(key: role_key).role_permissions_actions.pluck(:permission_key)
  end

  def strip(role_key)
    Role.find_by!(key: role_key).role_permissions_actions.where(permission_key: key).destroy_all
  end

  describe '#up' do
    it 'grants the definitions read to the agent role' do
      strip('agent')
      expect(keys('agent')).not_to include(key)

      migration.up

      expect(keys('agent')).to include(key)
    end

    it 'is idempotent — re-running does not duplicate the grant' do
      strip('agent')

      migration.up
      migration.up

      expect(keys('agent').count(key)).to eq(1)
    end

    it 'grants only the read — create/update/delete stay administrative' do
      strip('agent')

      migration.up

      %w[
        custom_attribute_definitions.create
        custom_attribute_definitions.update
        custom_attribute_definitions.delete
      ].each { |admin_key| expect(keys('agent')).not_to include(admin_key) }
    end

    it 'is a no-op when the agent role is missing' do
      # System roles abort `destroy`, which would leave the row in place and make
      # this example vacuous — drop the flag first.
      Role.find_by!(key: 'agent').update_column(:system, false)
      Role.find_by!(key: 'agent').destroy!
      expect(Role.find_by(key: 'agent')).to be_nil

      expect { migration.up }.not_to raise_error
    end
  end

  describe '#down' do
    it 'revokes only the backfilled key' do
      migration.up
      migration.down

      expect(keys('agent')).not_to include(key)
      expect(keys('agent')).to include('conversations.read')
    end
  end
end
