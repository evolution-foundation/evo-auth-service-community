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
end
