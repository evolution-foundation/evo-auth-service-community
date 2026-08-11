# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260811120001_consolidate_write_grants.rb')

# Spec for the CRM-99 slice-1 data-migration that rewrites stored granular
# create/update grants of the 22 consolidated resources onto the coarse write.
# The rewrite is the transition mechanism (the role editor filters selections
# through the live catalog, so granular leftovers would be silently dropped on
# the first save); User::LEGACY_WRITE_ALIASES stays only as a safety net.
RSpec.describe ConsolidateWriteGrants do
  let(:migration) { described_class.new }

  before { migration.singleton_class.send(:public, :up, :down) }

  def make_role
    suffix = SecureRandom.hex(4)
    Role.create!(key: "role-#{suffix}", name: "Role #{suffix}", type: 'account', system: false)
  end

  # Persist a grant bypassing the catalog validation (granular keys of the
  # consolidated resources are no longer valid against the catalog).
  def grant_raw(role, permission_key)
    record = role.role_permissions_actions.build(permission_key: permission_key)
    record.save!(validate: false)
  end

  def keys(role)
    role.reload.role_permissions_actions.pluck(:permission_key)
  end

  describe '#up' do
    it 'collapses create+update onto a single write row' do
      role = make_role
      grant_raw(role, 'labels.create')
      grant_raw(role, 'labels.update')

      expect { migration.up }.not_to raise_error

      expect(keys(role)).to contain_exactly('labels.write')
    end

    it 'promotes a create-only role to write (the escalation the card accepted)' do
      role = make_role
      grant_raw(role, 'teams.create')

      migration.up

      expect(keys(role)).to contain_exactly('teams.write')
    end

    it 'promotes an update-only role to write' do
      role = make_role
      grant_raw(role, 'pipelines.update')

      migration.up

      expect(keys(role)).to contain_exactly('pipelines.write')
    end

    it 'dedups when the role already holds the coarse write (unique-index-safe)' do
      role = make_role
      grant_raw(role, 'canned_responses.write')
      grant_raw(role, 'canned_responses.create')
      grant_raw(role, 'canned_responses.update')

      expect { migration.up }.not_to raise_error

      expect(keys(role)).to contain_exactly('canned_responses.write')
    end

    it 'covers all 22 consolidated resources' do
      role = make_role
      described_class::RESOURCES.each { |r| grant_raw(role, "#{r}.create") }

      migration.up

      expect(keys(role)).to match_array(described_class::RESOURCES.map { |r| "#{r}.write" })
    end

    it 'leaves read/delete and non-consolidated resources untouched' do
      role = make_role
      grant_raw(role, 'labels.read')
      grant_raw(role, 'labels.delete')
      grant_raw(role, 'macros.create')
      grant_raw(role, 'conversations.update')

      migration.up

      expect(keys(role)).to contain_exactly(
        'labels.read', 'labels.delete', 'macros.create', 'conversations.update'
      )
    end

    it 'is idempotent' do
      role = make_role
      grant_raw(role, 'products.create')
      grant_raw(role, 'products.update')

      expect do
        migration.up
        migration.up
      end.not_to raise_error

      expect(keys(role)).to contain_exactly('products.write')
    end

    it 'matches the slice-1 snapshot of the catalog constant' do
      # If a later slice grows CONSOLIDATED_WRITE_RESOURCES, this migration must
      # NOT change — the new resources get their own paired migration.
      expect(described_class::RESOURCES.map(&:to_sym))
        .to match_array(ResourceActionsConfig::CONSOLIDATED_WRITE_RESOURCES.to_a)
    end
  end

  describe 'system roles (seeded) keep every capability' do
    before { load Rails.root.join('db/seeds/rbac.rb') }

    it 'is a no-op on freshly seeded roles (seed already grants write)' do
      before_keys = Role.find_by!(key: 'account_owner').role_permissions_actions.pluck(:permission_key)

      migration.up

      expect(keys(Role.find_by!(key: 'account_owner'))).to match_array(before_keys)
    end

    it 'leaves super_admin holding all catalog keys' do
      migration.up

      expect(keys(Role.find_by!(key: 'super_admin'))).to match_array(ResourceActionsConfig.all_permission_keys)
    end
  end

  describe '#down' do
    it 'is a non-reversible no-op' do
      role = make_role
      grant_raw(role, 'labels.write')

      expect { migration.down }.not_to raise_error
      expect(keys(role)).to contain_exactly('labels.write')
    end
  end
end
