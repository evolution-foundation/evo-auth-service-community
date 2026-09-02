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

    it 'grants pipeline_items.update (dedicated card-write key) but NOT the manager-level pipelines.update/.create/.delete' do
      # Card writes (move/create/edit) gate on pipeline_items.update in the CRM
      # (PipelinePolicy#update_items?); pipelines.update stays the manager power to
      # reshape/archive the funnel and is deliberately withheld (CRM-178).
      expect(agent_permissions).to include('pipeline_items.update')
      expect(agent_permissions).not_to include('pipelines.update')
      expect(agent_permissions).not_to include('pipelines.create')
      expect(agent_permissions).not_to include('pipelines.delete')
    end

    it 'keeps stage read/create/update for the kanban experience but NOT the destructive stage delete' do
      %w[pipeline_stages.read pipeline_stages.create pipeline_stages.update].each do |key|
        expect(agent_permissions).to include(key)
      end
      expect(agent_permissions).not_to include('pipeline_stages.delete')
    end
  end

  describe 'agent role sanity-check for adjacent areas (regression guard)' do
    it 'keeps conversations read/create/update but NOT the destructive delete (least-privilege)' do
      %w[conversations.read conversations.create conversations.update].each do |key|
        expect(agent_permissions).to include(key)
      end
      # Closing/resolving a conversation is conversations.toggle_status (kept), not delete.
      expect(agent_permissions).to include('conversations.toggle_status')
      expect(agent_permissions).not_to include('conversations.delete')
    end

    it 'keeps contacts read/create/update but NOT the destructive delete (least-privilege)' do
      %w[contacts.read contacts.create contacts.update].each do |key|
        expect(agent_permissions).to include(key)
      end
      expect(agent_permissions).not_to include('contacts.delete')
    end

    it 'grants only teams.read — the agent must not create/update/delete teams or manage members' do
      # teams.update also gates team_members (add/remove members). Creating, renaming
      # and deleting teams is a manager/settings action, not attendance.
      expect(agent_permissions).to include('teams.read')
      %w[teams.create teams.update teams.delete].each do |key|
        expect(agent_permissions).not_to include(key)
      end
    end

    it 'does NOT grant accounts.delete or accounts.create (admin-only)' do
      expect(agent_permissions).not_to include('accounts.delete')
      expect(agent_permissions).not_to include('accounts.create')
    end

    it 'keeps read/create/update for labels and canned responses but NOT their destructive delete (CRM-190)' do
      # Deleting a shared asset affects the whole account (e.g. deleting a label
      # removes it from every conversation) — a manager action, not attendance.
      # By product decision (CRM-70) the agent manages its own labels and canned
      # responses, so create/update stay.
      %w[labels.read labels.create labels.update
         canned_responses.read canned_responses.create canned_responses.update].each do |key|
        expect(agent_permissions).to include(key)
      end
      %w[labels.delete macros.delete canned_responses.delete message_templates.delete].each do |key|
        expect(agent_permissions).not_to include(key)
      end
    end

    # CRM-70 use-vs-manage: the agent USES macros and templates in the chat but
    # does not manage them — create/update and the Settings screen are `.manage`.
    it 'keeps macros.read/execute and message_templates.read but not create/update nor manage' do
      %w[macros.read macros.execute message_templates.read].each do |key|
        expect(agent_permissions).to include(key)
      end
      %w[macros.create macros.update macros.manage
         message_templates.create message_templates.update message_templates.manage
         teams.manage].each do |key|
        expect(agent_permissions).not_to include(key)
      end
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

  # Anti-drift guard for the installation owner (grant-backed, no bypass).
  #
  # Stubbed catalog on purpose: asserting `all_permission_keys -
  # super_admin_permissions == []` is a tautology — the seed derives the grants
  # from that same method, so it stays green while the catalog grows, the exact
  # scenario this guards. The stub is an independent oracle for the seed POLICY
  # (super_admin takes the catalog whole; account_owner minus its two exclusives)
  # and fails if the seed ever adds a super_admin exclusion. Real keys because
  # RolePermissionsAction validates permission_key against the catalog.
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
  # see-all-inboxes grant; it is SECURE-BY-DEFAULT withheld from the agent (which
  # then sees only its member inboxes), while account_owner/super_admin keep it.
  # users.manage is the administrative gate and must NOT reach the agent role.
  describe 'agent role — RBAC split (operational reads, no admin gate)' do
    it 'explicitly grants users.read (operational read for the Conversations screen)' do
      expect(agent_permissions).to include('users.read')
    end

    it 'explicitly grants inboxes.read' do
      expect(agent_permissions).to include('inboxes.read')
    end

    it 'does NOT grant conversations.read_all (secure-by-default: agent sees only its member inboxes)' do
      # Without read_all, User#assigned_inboxes returns only the agent's inbox_members
      # (none => sees nothing until assigned). account_owner/super_admin keep read_all.
      expect(agent_permissions).not_to include('conversations.read_all')
    end

    it 'does NOT grant users.manage (agents never see the administrative panel)' do
      expect(agent_permissions).not_to include('users.manage')
    end
  end

  # EVO-1938: administrative Settings resources must not reach the default agent.
  # The frontend routes/menu and the CRM controllers gate by these permission
  # keys, so granting them is exactly what let an attendant see/manage admin-only
  # Settings screens. Operational resources used inside conversations stay; the
  # use-vs-manage split of macros/templates/teams landed with CRM-70.
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

    it 'admin roles receive the CRM-70 manage keys automatically' do
      %w[macros.manage message_templates.manage teams.manage].each do |key|
        expect(account_owner_permissions).to include(key)
        expect(super_admin_permissions).to include(key)
      end
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

  # CRM-166. The value-write keys asserted below are the evidence the missing read
  # was a gap and not a policy: writing values without reading the definitions that
  # describe them is not a coherent permission set.
  describe 'custom_attribute_definitions.read — CRM-166' do
    it 'is a valid permission registered in ResourceActionsConfig' do
      expect(ResourceActionsConfig.valid_permission?('custom_attribute_definitions.read')).to be true
    end

    it 'is granted to the agent role' do
      expect(agent_permissions).to include('custom_attribute_definitions.read')
    end

    it 'pairs with the custom-attribute VALUE writes the agent already had' do
      expect(agent_permissions).to include('conversations.custom_attributes')
      expect(agent_permissions).to include('contacts.destroy_custom_attributes')
    end

    it 'does NOT grant create/update/delete (managing definitions stays administrative)' do
      %w[
        custom_attribute_definitions.create
        custom_attribute_definitions.update
        custom_attribute_definitions.delete
      ].each { |key| expect(agent_permissions).not_to include(key) }
    end

    it 'is granted to account_owner and super_admin via all_permission_keys' do
      expect(account_owner_permissions).to include('custom_attribute_definitions.read')
      expect(super_admin_permissions).to include('custom_attribute_definitions.read')
    end
  end
end
