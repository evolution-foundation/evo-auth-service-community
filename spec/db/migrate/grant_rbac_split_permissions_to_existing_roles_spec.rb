# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260622120001_grant_rbac_split_permissions_to_existing_roles.rb')

# Spec for the paired data-migration that backfills the RBAC permission split
# (tech-spec rbac-granular-inbox-permissions) into already-bootstrapped
# installations. The biggest risk of the whole change lives here: if the
# migration does not grant the operational reads to EVERY existing role, custom
# roles that today work only via the BASIC inheritance would lose users.read /
# inboxes.read on upgrade and break the Conversations screen.
RSpec.describe GrantRbacSplitPermissionsToExistingRoles do
  let(:migration) { described_class.new }

  before { migration.singleton_class.send(:public, :up, :down) }

  # The "administrative gate" examples reference the seeded system roles
  # (account_owner / super_admin / agent) via find_by!. Seed them so those
  # rows exist; the "every existing role" examples create their own custom roles
  # and are unaffected by the seed.
  before { load Rails.root.join('db/seeds/rbac.rb') }

  def role_with(*permission_keys, key:, type: 'account')
    role = Role.create!(key: key, name: key.titleize, type: type, system: false)
    permission_keys.each { |pk| role.role_permissions_actions.create!(permission_key: pk) }
    role
  end

  def keys(role)
    role.reload.role_permissions_actions.pluck(:permission_key)
  end

  describe '#up — operational reads to every existing role' do
    it 'grants users.read, inboxes.read and conversations.read_all to a plain custom role' do
      role = role_with('conversations.read', key: "converse-#{SecureRandom.hex(4)}")

      migration.up

      expect(keys(role)).to include('users.read', 'inboxes.read', 'conversations.read_all')
    end

    it 'is idempotent — re-running does not duplicate keys' do
      role = role_with('conversations.read', key: "converse-#{SecureRandom.hex(4)}")

      migration.up
      migration.up

      expect(keys(role).count('users.read')).to eq(1)
    end
  end

  describe '#up — administrative gate (users.manage)' do
    # account_owner / super_admin are seeded system roles (unique key
    # constraint) — reuse them via find_by!. Strip users.manage first so the
    # assertion exercises the migration's grant, not the seed's.
    it 'grants users.manage to account_owner (ADMIN_ROLE_KEYS branch)' do
      role = Role.find_by!(key: 'account_owner')
      role.role_permissions_actions.where(permission_key: 'users.manage').destroy_all

      migration.up

      expect(keys(role)).to include('users.manage')
    end

    it 'grants users.manage to super_admin (ADMIN_ROLE_KEYS branch)' do
      role = Role.find_by!(key: 'super_admin')
      role.role_permissions_actions.where(permission_key: 'users.manage').destroy_all

      migration.up

      expect(keys(role)).to include('users.manage')
    end

    it 'grants users.manage to a custom administrative role (has users.update)' do
      role = role_with('conversations.read', 'users.update', key: "gerente-#{SecureRandom.hex(4)}")

      migration.up

      expect(keys(role)).to include('users.manage')
    end

    it 'does NOT grant users.manage to a non-administrative custom role' do
      role = role_with('conversations.read', key: "plain-#{SecureRandom.hex(4)}")

      migration.up

      expect(keys(role)).not_to include('users.manage')
    end

    it 'does NOT grant users.manage to the seeded agent role' do
      role = Role.find_by!(key: 'agent')
      role.role_permissions_actions.where(permission_key: 'users.manage').destroy_all

      migration.up

      expect(keys(role)).not_to include('users.manage')
    end
  end

  describe '#down — symmetric removal' do
    it 'strips the four added keys from the roles it touched' do
      role = role_with('conversations.read', 'users.update', key: "gerente-#{SecureRandom.hex(4)}")

      migration.up
      expect(keys(role)).to include('users.read', 'inboxes.read', 'conversations.read_all', 'users.manage')

      migration.down

      expect(keys(role)).not_to include('users.read', 'inboxes.read', 'conversations.read_all', 'users.manage')
      # The role's original, unrelated permission survives.
      expect(keys(role)).to include('conversations.read', 'users.update')
    end
  end
end
