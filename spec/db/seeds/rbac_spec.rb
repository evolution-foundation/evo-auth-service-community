# frozen_string_literal: true

require 'rails_helper'

# Regression guard for the agent role permission set seeded by
# db/seeds/rbac.rb. A misadjusted permission key here silently changes what
# every default agent in every fresh install can do — the seed runs
# `destroy_all` then re-creates from the array, so the on-disk array is the
# source of truth at install time. The agent role specifically came up in
# the PR #14 review of EVO-1060: `pipelines.update` had been added under the
# assumption it was required for kanban drag-and-drop, but the controller
# only checks `pipelines.read`. `pipelines.update` would also have unlocked
# destructive endpoints (archive, set_as_default, rename of shared
# pipelines) without product authorisation. This spec exists so the same
# slip cannot recur unnoticed.

RSpec.describe 'db/seeds/rbac.rb', type: :model do
  before do
    Role.find_each(&:destroy)
    ResourceActionsConfig.refresh! if ResourceActionsConfig.respond_to?(:refresh!)
    load Rails.root.join('db/seeds/rbac.rb')
  end

  let(:agent_role) { Role.find_by(key: 'agent') }
  let(:account_owner_role) { Role.find_by(key: 'account_owner') }
  let(:super_admin_role) { Role.find_by(key: 'super_admin') }

  let(:agent_permissions) { agent_role.role_permissions_actions.pluck(:permission_key) }
  let(:account_owner_permissions) { account_owner_role.role_permissions_actions.pluck(:permission_key) }
  let(:super_admin_permissions) { super_admin_role.role_permissions_actions.pluck(:permission_key) }

  describe 'agent role pipelines permissions' do
    it 'includes pipelines.read so the menu entry and route are reachable' do
      expect(agent_permissions).to include('pipelines.read')
    end

    it 'does NOT include pipelines.update, .create, or .delete (destructive endpoints stay admin-only)' do
      expect(agent_permissions).not_to include('pipelines.update')
      expect(agent_permissions).not_to include('pipelines.create')
      expect(agent_permissions).not_to include('pipelines.delete')
    end

    it 'keeps the related stage-level permissions for the kanban experience' do
      %w[pipeline_stages.read pipeline_stages.create pipeline_stages.update pipeline_stages.delete].each do |key|
        expect(agent_permissions).to include(key)
      end
    end
  end

  describe 'agent role sanity-check for adjacent areas (regression guard)' do
    it 'keeps conversations CRUD (otherwise agents cannot do their job)' do
      %w[conversations.read conversations.create conversations.update conversations.delete].each do |key|
        expect(agent_permissions).to include(key)
      end
    end

    it 'keeps contacts CRUD (agents need to manage contacts)' do
      %w[contacts.read contacts.create contacts.update contacts.delete].each do |key|
        expect(agent_permissions).to include(key)
      end
    end

    it 'does NOT grant accounts.delete or accounts.create (admin-only)' do
      expect(agent_permissions).not_to include('accounts.delete')
      expect(agent_permissions).not_to include('accounts.create')
    end
  end

  # AC5 of EVO-1060: "No regression for account_owner or super_admin (they
  # retain full access)". The agent-side adjustments must not bleed into the
  # other roles, and the installation-level boundary (only super_admin can
  # render /settings/admin) must hold.
  describe 'account_owner role boundary' do
    it 'keeps account-scoped CRUD (sanity check that the seed still ran)' do
      expect(account_owner_permissions).to include('conversations.read')
      expect(account_owner_permissions).to include('pipelines.read')
    end

    it 'does NOT hold installation_configs.manage (reserved for super_admin)' do
      expect(account_owner_permissions).not_to include('installation_configs.manage')
    end
  end

  # Anti-drift invariant. Nothing bypasses RBAC for the installation owner: the
  # resource gate and the /permissions endpoint are row-based and the frontend
  # `can()` is data-driven, so the admin can do exactly what the seed granted.
  # If a new catalog entry ever fails to reach super_admin, the backend 403s the
  # admin on the new feature and the frontend hides the control — silently.
  # These examples are the tripwire; RbacGrantReconciler is the runtime repair.
  #
  # They deliberately drive the seed through a STUBBED catalog instead of
  # comparing the seeded grants against `all_permission_keys`. Asserting
  # `all_permission_keys - super_admin_permissions == []` reads like a guard but
  # is a tautology: the seed derives super_admin's grants from that very method,
  # so the two sides are the same expression and the example cannot fail — it
  # stays green even when the catalog grows, which is precisely the scenario it
  # was meant to catch. Stubbing gives the assertion an INDEPENDENT oracle: a
  # known five-key catalog, against which the seed's *policy* (super_admin takes
  # the catalog whole; account_owner takes it minus exactly the two documented
  # exclusives) is a real, falsifiable claim. Introduce a `super_admin_exclusive`
  # filter in the seed and these fail.
  #
  # The stub uses real catalog keys because RolePermissionsAction validates
  # permission_key against ResourceActionsConfig — a fabricated key would be
  # rejected at create! and mask the assertion.
  describe 'super_admin grant set == full permission catalog (seed policy)' do
    STUBBED_CATALOG = %w[
      contacts.read
      contacts.create
      users.manage
      accounts.stats
      installation_configs.manage
    ].freeze

    before do
      allow(ResourceActionsConfig).to receive(:all_permission_keys).and_return(STUBBED_CATALOG)
      Role.find_each { |role| role.role_permissions_actions.delete_all }
      load Rails.root.join('db/seeds/rbac.rb')
    end

    it 'grants super_admin the catalog WHOLE — no exclusion list of its own' do
      expect(super_admin_permissions).to match_array(STUBBED_CATALOG)
    end

    it 'withholds from account_owner exactly the two documented exclusives' do
      expect(account_owner_permissions)
        .to match_array(STUBBED_CATALOG - %w[accounts.stats installation_configs.manage])
    end

    it 'is the only role holding the installation-level key' do
      installation_owners = Role.all.select do |role|
        role.role_permissions_actions.exists?(permission_key: 'installation_configs.manage')
      end

      expect(installation_owners.map(&:key)).to eq(['super_admin'])
    end
  end

  describe 'super_admin role boundary' do
    it 'holds installation_configs.manage (the whole reason this role exists)' do
      expect(super_admin_permissions).to include('installation_configs.manage')
    end

    it 'also holds the account-scoped permissions account_owner has' do
      expect(super_admin_permissions).to include('conversations.read')
      expect(super_admin_permissions).to include('pipelines.read')
    end
  end

  # RBAC permission split (tech-spec rbac-granular-inbox-permissions).
  # users.read / inboxes.read were removed from BASIC_READ_PERMISSIONS, so the
  # seeded roles must now grant them explicitly. conversations.read_all is the
  # opt-in that preserves "see all inboxes" for the default roles. users.manage
  # is the administrative gate and must NOT reach the agent role.
  describe 'agent role — RBAC split (operational reads, no admin gate)' do
    it 'explicitly grants users.read (operational read for the Conversations screen)' do
      expect(agent_permissions).to include('users.read')
    end

    it 'explicitly grants inboxes.read' do
      expect(agent_permissions).to include('inboxes.read')
    end

    it 'grants conversations.read_all so agents keep seeing every inbox by default' do
      expect(agent_permissions).to include('conversations.read_all')
    end

    it 'does NOT grant users.manage (agents never see the administrative panel)' do
      expect(agent_permissions).not_to include('users.manage')
    end
  end

  # EVO-1938: administrative Settings resources must not reach the default agent.
  # The frontend routes/menu and the CRM controllers gate by these permission
  # keys, so granting them is exactly what let an attendant see/manage admin-only
  # Settings screens. Operational resources used inside conversations stay (their
  # use-vs-manage split is the EVO-1955 follow-up).
  describe 'agent role — EVO-1938 administrative Settings exclusion' do
    # `agents` became `ai_agents` (EVO-2072 consolidated the dead twin); the guard
    # tracks the surviving resource — the attendant must not manage AI agents.
    admin_only_resources = %w[
      ai_agents agent_bots ai_chat_sessions
      integrations working_hours segments journeys campaigns
    ]

    admin_only_resources.each do |resource|
      it "does NOT grant any #{resource}.* permission to the agent" do
        expect(agent_permissions.select { |k| k.start_with?("#{resource}.") }).to be_empty
      end
    end

    it 'keeps the operational resources agents use inside conversations' do
      # teams.read powers the in-chat "Assign team" picker, so it stays operational.
      %w[labels.read canned_responses.read macros.execute message_templates.read teams.read].each do |key|
        expect(agent_permissions).to include(key)
      end
    end

    it 'still grants the administrative resources to account_owner' do
      # agents.read -> ai_agents.read (EVO-2072 consolidation; same capability).
      %w[integrations.read campaigns.read ai_agents.read].each do |key|
        expect(account_owner_permissions).to include(key)
      end
    end
  end

  describe 'account_owner / super_admin — RBAC split (administrative gate)' do
    it 'account_owner receives users.manage automatically via all_permission_keys' do
      expect(account_owner_permissions).to include('users.manage')
    end

    it 'account_owner receives conversations.read_all automatically' do
      expect(account_owner_permissions).to include('conversations.read_all')
    end

    it 'super_admin holds users.manage and conversations.read_all' do
      expect(super_admin_permissions).to include('users.manage')
      expect(super_admin_permissions).to include('conversations.read_all')
    end
  end

  describe 'conversations.import — EVO-1557 catalog + role grants' do
    it 'is a valid permission registered in ResourceActionsConfig' do
      expect(ResourceActionsConfig.valid_permission?('conversations.import')).to be true
    end

    it 'is granted to the agent role (mirrors contacts.import precedent)' do
      expect(agent_permissions).to include('conversations.import')
    end

    it 'is granted to account_owner via all_permission_keys' do
      expect(account_owner_permissions).to include('conversations.import')
    end

    it 'is granted to super_admin via all_permission_keys' do
      expect(super_admin_permissions).to include('conversations.import')
    end
  end
end
