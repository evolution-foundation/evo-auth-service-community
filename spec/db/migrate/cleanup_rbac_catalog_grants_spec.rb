# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260708120000_cleanup_rbac_catalog_grants.rb')

# Spec for the EVO-2070 data-migration that reconciles stored grants with the
# trimmed RBAC catalog. On an already-bootstrapped install, role_permissions_actions
# still carries rows for keys that were removed (dead resources) or consolidated
# (team_members -> teams, permissions -> roles.read). The migration must delete
# the dead ones and rewrite the consolidated ones WITHOUT tripping the unique
# index (role_id, permission_key), all while leaving every surviving capability
# — and the system roles — intact.
RSpec.describe CleanupRbacCatalogGrants do
  let(:migration) { described_class.new }

  before { migration.singleton_class.send(:public, :up, :down) }

  def make_role
    suffix = SecureRandom.hex(4)
    Role.create!(key: "role-#{suffix}", name: "Role #{suffix}", type: 'account', system: false)
  end

  # Persist a grant bypassing the catalog validation (the point of the migration
  # is to clean up keys that are no longer valid, so we must be able to seed them).
  def grant_raw(role, permission_key)
    record = role.role_permissions_actions.build(permission_key: permission_key)
    record.save!(validate: false)
  end

  def keys(role)
    role.reload.role_permissions_actions.pluck(:permission_key)
  end

  describe '#up' do
    it 'deletes grants for fully removed resources' do
      role = make_role
      # ai_tools/ai_folders/ai_mcp_servers are intentionally NOT here — the audit
      # kept them (live core/processor enforcement); the migration must leave
      # their grants alone (see the preservation test below).
      %w[channels.read
         oauth_contacts.read oauth_agents.read oauth_pipelines.read
         oauth_pipeline_stages.read agent_apikeys.read agent_folders.read
         agent_shared_folders.read reports.read live_reports.read
         summary_reports.read].each { |k| grant_raw(role, k) }

      migration.up

      expect(keys(role)).to be_empty
    end

    it 'renames a lone consolidated key in place' do
      role = make_role
      grant_raw(role, 'team_members.read')
      grant_raw(role, 'permissions.read')

      migration.up

      expect(keys(role)).to contain_exactly('teams.read', 'roles.read')
    end

    it 'dedups when the target key already exists (unique-index-safe)' do
      role = make_role
      grant_raw(role, 'teams.read')
      grant_raw(role, 'team_members.read')

      expect { migration.up }.not_to raise_error

      expect(keys(role)).to contain_exactly('teams.read')
    end

    it 'collapses the three team_members mutations onto a single teams.update' do
      role = make_role
      grant_raw(role, 'team_members.create')
      grant_raw(role, 'team_members.update')
      grant_raw(role, 'team_members.delete')

      expect { migration.up }.not_to raise_error

      expect(keys(role)).to contain_exactly('teams.update')
    end

    it 'preserves surviving grants kept by the audit (ai_tools/ai_folders/ai_mcp_servers)' do
      role = make_role
      grant_raw(role, 'conversations.read')
      grant_raw(role, 'teams.read')
      grant_raw(role, 'ai_tools.read')
      grant_raw(role, 'ai_folders.read')
      grant_raw(role, 'ai_mcp_servers.read')
      grant_raw(role, 'channels.read')

      migration.up

      expect(keys(role)).to contain_exactly(
        'conversations.read', 'teams.read', 'ai_tools.read',
        'ai_folders.read', 'ai_mcp_servers.read'
      )
    end

    it 'is idempotent' do
      role = make_role
      grant_raw(role, 'team_members.create')
      grant_raw(role, 'channels.read')

      expect do
        migration.up
        migration.up
      end.not_to raise_error

      expect(keys(role)).to contain_exactly('teams.update')
    end
  end

  describe 'system roles (seeded) keep every capability' do
    before { load Rails.root.join('db/seeds/rbac.rb') }

    it 'leaves super_admin holding all catalog keys after the migration' do
      migration.up

      super_admin = Role.find_by!(key: 'super_admin')
      expect(keys(super_admin)).to match_array(ResourceActionsConfig.all_permission_keys)
    end

    it 'leaves account_owner with the consolidated capabilities intact' do
      migration.up

      account_owner = Role.find_by!(key: 'account_owner')
      expect(keys(account_owner)).to include('teams.read', 'teams.update', 'roles.read')
      # No stale/consolidated keys leaked back in.
      expect(keys(account_owner)).not_to include('team_members.read', 'permissions.read', 'channels.read')
    end
  end

  describe '#down' do
    it 'is a non-reversible no-op' do
      role = make_role
      grant_raw(role, 'teams.read')

      expect { migration.down }.not_to raise_error
      expect(keys(role)).to contain_exactly('teams.read')
    end
  end
end
