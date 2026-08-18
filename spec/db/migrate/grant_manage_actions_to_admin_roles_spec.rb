# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260818120001_grant_manage_actions_to_admin_roles.rb')

# The catalog gained macros/message_templates/teams `.manage` (CRM-70). On a
# bootstrapped installation that only runs `db:migrate`, no role would hold them
# and the Settings screens (now gated by `.manage`) would ship dark for admins.
# This pins the backfill: admin roles get the three keys, the agent role is left
# alone, and re-running never duplicates rows.
RSpec.describe GrantManageActionsToAdminRoles do
  let(:migration) { described_class.new }
  let(:all_keys) { described_class::PERMISSIONS }

  before { migration.singleton_class.send(:public, :up, :down) }
  before { load Rails.root.join('db/seeds/rbac.rb') }

  def keys(role_key)
    Role.find_by!(key: role_key).role_permissions_actions.pluck(:permission_key)
  end

  def strip(role_key)
    Role.find_by!(key: role_key).role_permissions_actions.where(permission_key: all_keys).destroy_all
  end

  describe '#up' do
    it 'grants macros/message_templates/teams manage to account_owner and super_admin' do
      strip('account_owner')
      strip('super_admin')

      migration.up

      expect(keys('account_owner')).to include(*all_keys)
      expect(keys('super_admin')).to include(*all_keys)
    end

    it 'leaves the agent role without any manage key' do
      migration.up

      expect(keys('agent')).not_to include(*all_keys)
    end

    it 'is idempotent — re-running does not duplicate keys' do
      strip('account_owner')

      migration.up
      migration.up

      all_keys.each { |key| expect(keys('account_owner').count(key)).to eq(1) }
    end

    it 'is a no-op when a role is missing' do
      Role.find_by!(key: 'super_admin').update_column(:system, false)
      Role.find_by!(key: 'super_admin').destroy!
      expect(Role.find_by(key: 'super_admin')).to be_nil

      expect { migration.up }.not_to raise_error
      expect(keys('account_owner')).to include(*all_keys)
    end
  end

  describe '#down' do
    it 'revokes only the backfilled keys from the admin roles' do
      migration.up
      migration.down

      expect(keys('account_owner')).not_to include(*all_keys)
      expect(keys('account_owner')).to include('conversations.read')
    end
  end
end
