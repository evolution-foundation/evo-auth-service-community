# frozen_string_literal: true

require 'rails_helper'

# CRM-99 — collapse granular create/update into the coarse `write` for the
# stray-verb-free resources (ResourceActionsConfig::CONSOLIDATED_WRITE_RESOURCES).
# Transition path (b): create/update leave the catalog, but a role still holding a
# removed grant keeps satisfying write via User::LEGACY_WRITE_ALIASES — the card's
# hard rule of "no silent privilege revocation".
RSpec.describe 'RBAC write consolidation (CRM-99)', type: :model do
  def build_user
    User.create!(name: 'Perm User', email: "perm-#{SecureRandom.hex(4)}@example.com",
                 password: 'Valid1!Pass', password_confirmation: 'Valid1!Pass', confirmed_at: Time.current)
  end

  def role_with(*permission_keys)
    role = Role.create!(key: "role-#{SecureRandom.hex(4)}", name: 'R', type: 'account', system: false)
    permission_keys.each { |pk| role.role_permissions_actions.create!(permission_key: pk) }
    role
  end

  def assign(user, role) = UserRole.assign_role_to_user(user, role)

  describe 'catalog' do
    it 'exposes a first-class write and drops create/update on a consolidated resource' do
      expect(ResourceActionsConfig.valid_permission?('labels.write')).to be(true)
      expect(ResourceActionsConfig.valid_permission?('labels.create')).to be(false)
      expect(ResourceActionsConfig.valid_permission?('labels.update')).to be(false)
    end

    it 'keeps read/delete on a consolidated resource' do
      expect(ResourceActionsConfig.valid_permission?('labels.read')).to be(true)
      expect(ResourceActionsConfig.valid_permission?('labels.delete')).to be(true)
    end

    it 'leaves a stray-verb resource (conversations) untouched — that is a later slice' do
      expect(ResourceActionsConfig.valid_permission?('conversations.create')).to be(true)
      expect(ResourceActionsConfig.valid_permission?('conversations.update')).to be(true)
    end
  end

  # AC5 — a role without write is barred; a role with write passes. Real keys, real DB.
  describe 'enforcement' do
    it 'a role granted labels.write passes a labels.write check' do
      user = build_user
      assign(user, role_with('labels.write'))
      expect(user.has_permission?('labels.write')).to be(true)
    end

    it 'a role without write is barred from labels.write' do
      user = build_user
      assign(user, role_with('labels.read'))
      expect(user.has_permission?('labels.write')).to be(false)
    end
  end

  # AC4 — the legacy grant a custom role still stores must keep resolving to write.
  describe 'legacy alias (no silent privilege revocation)' do
    it 'a role still holding the removed labels.create keeps satisfying labels.write' do
      user = build_user
      assign(user, role_with('labels.create'))
      expect(user.has_permission?('labels.write')).to be(true)
    end

    it 'labels.update (legacy) also still satisfies write' do
      user = build_user
      assign(user, role_with('labels.update'))
      expect(user.has_permission?('labels.write')).to be(true)
    end

    it 'all_permissions surfaces the implied write so the frontend agrees' do
      user = build_user
      assign(user, role_with('teams.create'))
      expect(user.all_permissions).to include('teams.write')
    end
  end
end
