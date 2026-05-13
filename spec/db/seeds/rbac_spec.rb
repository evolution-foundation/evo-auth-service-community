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
  let(:agent_role) do
    load Rails.root.join('db/seeds/rbac.rb')
    Role.find_by(key: 'agent')
  end

  let(:agent_permissions) do
    agent_role.role_permissions_actions.pluck(:permission_key)
  end

  before do
    Role.find_each(&:destroy)
    ResourceActionsConfig.refresh! if ResourceActionsConfig.respond_to?(:refresh!)
  end

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
end
