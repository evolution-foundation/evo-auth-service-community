# frozen_string_literal: true

require 'rails_helper'

# The installation owner has no RBAC bypass: the resource gate, the /permissions
# endpoint and the frontend `can()` are all row-based. Full admin access exists
# only while `super_admin` holds the entire catalog. These examples cover the
# self-healing path used on every boot (docker-entrypoint.sh) — the guard that a
# catalog change can no longer strip capabilities from the admin in silence.
RSpec.describe RbacGrantReconciler do
  before { load Rails.root.join('db/seeds/rbac.rb') }

  let(:super_admin) { Role.find_by!(key: 'super_admin') }

  def keys
    super_admin.reload.role_permissions_actions.pluck(:permission_key)
  end

  # A grant whose key left the catalog cannot be created through the model
  # (RolePermissionsAction validates against ResourceActionsConfig), but rows
  # like this exist in installations that were seeded before the key was
  # removed — which is exactly the case the reconciler has to clean up.
  def add_legacy_grant(key)
    super_admin.role_permissions_actions.new(permission_key: key).save!(validate: false)
  end

  # System roles refuse `destroy` (Role#prevent_system_role_deletion), so a
  # pre-bootstrap database is simulated at the row level.
  def wipe_roles!
    RolePermissionsAction.delete_all
    UserRole.delete_all
    Role.delete_all
  end

  describe '.drifted?' do
    it 'is false right after the seed (the seed grants the whole catalog)' do
      expect(described_class.drifted?).to be false
    end

    it 'is true when a catalog permission is missing from the role' do
      super_admin.role_permissions_actions.find_by!(permission_key: 'installation_configs.manage').destroy

      expect(described_class.drifted?).to be true
      expect(described_class.missing_keys).to eq(['installation_configs.manage'])
    end

    it 'is true when the role carries a grant the catalog no longer defines' do
      add_legacy_grant('removed_resource.manage')

      expect(described_class.drifted?).to be true
      expect(described_class.stale_keys).to eq(['removed_resource.manage'])
    end

    it 'is false when the role does not exist yet (installation not bootstrapped)' do
      wipe_roles!

      expect(described_class.drifted?).to be false
    end
  end

  describe '.reconcile!' do
    it 'grants back the catalog permissions the role lost' do
      %w[installation_configs.manage users.manage].each do |key|
        super_admin.role_permissions_actions.find_by!(permission_key: key).destroy
      end

      result = described_class.reconcile!

      expect(result[:added]).to eq(2)
      expect(keys).to include('installation_configs.manage', 'users.manage')
    end

    it 'drops grants that are no longer in the catalog' do
      add_legacy_grant('removed_resource.manage')

      result = described_class.reconcile!

      expect(result[:removed]).to eq(1)
      expect(keys).not_to include('removed_resource.manage')
    end

    it 'is idempotent — a second run is a no-op' do
      super_admin.role_permissions_actions.find_by!(permission_key: 'users.manage').destroy
      described_class.reconcile!

      expect(described_class.reconcile!).to include(added: 0, removed: 0)
      expect(keys.size).to eq(keys.uniq.size)
    end

    # Race between two booting replicas: the loser's insert conflicts on the
    # unique index and must be skipped, not roll the batch back. Simulated by
    # having `missing_keys` report a key the role already holds — the state the
    # loser sees at INSERT time.
    it 'survives a concurrent boot that already inserted part of the batch' do
      super_admin.role_permissions_actions.find_by!(permission_key: 'users.manage').destroy
      already_won = 'installation_configs.manage'
      allow(described_class).to receive(:missing_keys).and_return(['users.manage', already_won])

      expect { described_class.reconcile! }.not_to raise_error
      expect(keys).to include('users.manage', already_won)
      expect(keys.count(already_won)).to eq(1)
    end

    it 'is a safe no-op before bootstrap instead of raising' do
      wipe_roles!

      expect { described_class.reconcile! }.not_to raise_error
      expect(described_class.reconcile!).to include(role: nil, added: 0, removed: 0)
    end

    it 'leaves the other system roles untouched' do
      agent = Role.find_by!(key: 'agent')
      account_owner = Role.find_by!(key: 'account_owner')
      agent_before = agent.role_permissions_actions.pluck(:permission_key).sort
      owner_before = account_owner.role_permissions_actions.pluck(:permission_key).sort

      super_admin.role_permissions_actions.find_by!(permission_key: 'users.manage').destroy
      described_class.reconcile!

      expect(agent.reload.role_permissions_actions.pluck(:permission_key).sort).to eq(agent_before)
      expect(account_owner.reload.role_permissions_actions.pluck(:permission_key).sort).to eq(owner_before)
      expect(account_owner.role_permissions_actions.pluck(:permission_key)).not_to include('installation_configs.manage')
    end
  end
end
