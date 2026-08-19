# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260818120001_grant_manage_actions_to_managing_roles.rb')

# The catalog gained macros/message_templates/teams `.manage` (CRM-70). On a
# bootstrapped installation that only runs `db:migrate`, no role would hold them
# and the Settings screens (now gated by `.manage`) would ship dark. This pins the
# backfill: admin roles get the three keys, every role that can already manage the
# resource keeps that reach, the agent is left alone, and re-running never
# duplicates rows.
RSpec.describe GrantManageActionsToManagingRoles do
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

  # `name` is unique on Role, so it tracks the key — two custom roles inside one
  # example is the normal case here (a team writer next to a teams.read-only role).
  def custom_role(*permission_keys)
    key = "manager-#{SecureRandom.hex(4)}"
    Role.create!(key: key, name: "Manager #{key}", type: 'account', system: false).tap do |role|
      permission_keys.each { |pk| role.role_permissions_actions.create!(permission_key: pk) }
    end
  end

  def role_keys(role)
    role.reload.role_permissions_actions.pluck(:permission_key)
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

    # The agent still holds macros/message_templates create+update at this point
    # (RevokeManageWritesFromAgent runs after): matching the superseded keys must
    # not be enough to earn `.manage`, or the card would undo itself.
    it 'leaves the agent alone even while it still holds the superseded write keys' do
      agent = Role.find_by!(key: 'agent')
      %w[macros.create macros.update].each do |key|
        agent.role_permissions_actions.create!(permission_key: key) unless
          agent.role_permissions_actions.exists?(permission_key: key)
      end

      migration.up

      expect(keys('agent')).not_to include('macros.manage')
    end

    # CRM-70 is a gate split: without this the upgrade silently takes macro
    # management away from a custom role that has it today.
    it 'backfills a custom role that can already manage macros and templates' do
      custom = custom_role('macros.create', 'macros.update', 'message_templates.update')

      migration.up

      expect(role_keys(custom)).to include('macros.manage', 'message_templates.manage')
    end

    it 'backfills teams.manage from a team write, not from teams.read' do
      writer = custom_role('teams.update')
      reader = custom_role('teams.read')

      migration.up

      expect(role_keys(writer)).to include('teams.manage')
      # teams.read is in User::BASIC_READ_PERMISSIONS — every user holds it, so
      # keying off it would hand teams.manage to everyone and undo the card.
      expect(role_keys(reader)).not_to include('teams.manage')
    end

    it 'does not grant a resource the role cannot manage today' do
      custom = custom_role('macros.create')

      migration.up

      expect(role_keys(custom)).to include('macros.manage')
      expect(role_keys(custom)).not_to include('message_templates.manage', 'teams.manage')
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

    it 'revokes the backfilled key from a custom role but keeps its own writes' do
      custom = custom_role('macros.create', 'macros.update')

      migration.up
      migration.down

      expect(role_keys(custom)).not_to include('macros.manage')
      expect(role_keys(custom)).to include('macros.create', 'macros.update')
    end
  end
end
