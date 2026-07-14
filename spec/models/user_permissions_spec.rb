# frozen_string_literal: true

require 'rails_helper'

# Specs for the RBAC permission split (tech-spec rbac-granular-inbox-permissions).
#
#   - users.read / inboxes.read were removed from BASIC_READ_PERMISSIONS so they
#     no longer leak to every user (the dual-semantics bug).
#   - A role with conversations.read now receives users.read / inboxes.read
#     OPERATIONALLY (OPERATIONAL_IMPLICATIONS) so the Conversations screen keeps
#     working for a profile created AFTER the split — covers AC6 / AC6b.
#   - The implication must show up in BOTH has_permission? (API enforcement) and
#     all_permissions (read by the frontend PermissionsContext) so FE and BE
#     agree.
RSpec.describe User, type: :model do
  def build_user(email: nil)
    User.create!(
      name: 'Perm User',
      email: email || "perm-#{SecureRandom.hex(4)}@example.com",
      password: 'Valid1!Pass',
      password_confirmation: 'Valid1!Pass',
      confirmed_at: Time.current
    )
  end

  def role_with(*permission_keys, key: "role-#{SecureRandom.hex(4)}", type: 'account')
    role = Role.create!(key: key, name: key.titleize, type: type, system: false)
    permission_keys.each { |pk| role.role_permissions_actions.create!(permission_key: pk) }
    role
  end

  def assign(user, role)
    UserRole.assign_role_to_user(user, role)
  end

  describe 'BASIC_READ_PERMISSIONS no longer leaks users.read / inboxes.read' do
    it 'does not include users.read or inboxes.read' do
      expect(User::BASIC_READ_PERMISSIONS).not_to include('users.read')
      expect(User::BASIC_READ_PERMISSIONS).not_to include('inboxes.read')
    end

    it 'still includes the kept basic reads' do
      expect(User::BASIC_READ_PERMISSIONS).to include('accounts.read', 'labels.read', 'dashboard.read', 'teams.read')
    end

    it 'a user with no roles does NOT have users.read via inheritance' do
      user = build_user
      expect(user.has_permission?('users.read')).to be(false)
      expect(user.all_permissions).not_to include('users.read')
      expect(user.all_permissions).not_to include('inboxes.read')
    end
  end

  describe 'operational implication: conversations.read => users.read + inboxes.read' do
    let(:user) { build_user }

    before { assign(user, role_with('conversations.read')) }

    it 'has_permission?(users.read) is true (operational, AC6)' do
      expect(user.has_permission?('users.read')).to be(true)
    end

    it 'has_permission?(inboxes.read) is true (operational)' do
      expect(user.has_permission?('inboxes.read')).to be(true)
    end

    it 'all_permissions includes the implied reads so the frontend agrees (AC6b)' do
      expect(user.all_permissions).to include('users.read', 'inboxes.read', 'conversations.read')
    end

    it 'does NOT imply users.manage (administrative gate stays closed)' do
      expect(user.has_permission?('users.manage')).to be(false)
      expect(user.all_permissions).not_to include('users.manage')
    end
  end

  describe 'no implication without conversations.read' do
    let(:user) { build_user }

    before { assign(user, role_with('contacts.read')) }

    it 'does not grant users.read just from an unrelated role permission' do
      expect(user.has_permission?('users.read')).to be(false)
      expect(user.all_permissions).not_to include('users.read')
    end
  end

  describe 'explicit role permission still resolves' do
    let(:user) { build_user }

    before { assign(user, role_with('users.manage')) }

    it 'has_permission? returns true for an explicitly granted key' do
      expect(user.has_permission?('users.manage')).to be(true)
      expect(user.all_permissions).to include('users.manage')
    end
  end

  # EVO-2127: holding a granular write of a resource implies its coarse
  # <resource>.write, so a delegated admin who can grant the granular writes can
  # also grant the coarse write the role editor now sends (unblocks the 403 in
  # roles_controller#bulk_update_permissions). Forward-only: no cascade to delete.
  describe 'coarse write implication (EVO-2127)' do
    let(:user) { build_user }

    it 'implies ai_agents.write from ai_agents.create (AC4)' do
      assign(user, role_with('ai_agents.create'))
      expect(user.has_permission?('ai_agents.write')).to be(true)
      expect(user.all_permissions).to include('ai_agents.write')
    end

    it 'does not imply write from a read-only grant (AC5)' do
      assign(user, role_with('ai_agents.read'))
      expect(user.has_permission?('ai_agents.write')).to be(false)
      expect(user.all_permissions).not_to include('ai_agents.write')
    end

    it 'does not cascade write into delete (AC6)' do
      assign(user, role_with('ai_agents.create'))
      expect(user.has_permission?('ai_agents.delete')).to be(false)
    end

    it 'implies write only for the resource that holds the granular write' do
      assign(user, role_with('ai_agents.create'))
      expect(user.has_permission?('contacts.write')).to be(false)
    end
  end

  # EVO-2124: the "Testar Agente" panel opens the session with ai_agents.write and
  # then sends every message over POST /chat/{agent}/{session}, which the processor
  # gates on ai_agent_processor.execute — a system key with no checkbox and no seed.
  # Whoever can write the agent must therefore be able to run it, or the panel 403s
  # on the first message for exactly the role an admin ticked "AI Agents" for.
  describe 'agent execution implication (EVO-2124)' do
    let(:user) { build_user }

    it 'implies ai_agent_processor.execute from the coarse ai_agents.write' do
      assign(user, role_with('ai_agents.write'))
      expect(user.has_permission?('ai_agent_processor.execute')).to be(true)
      expect(user.all_permissions).to include('ai_agent_processor.execute')
    end

    it 'implies execute from a granular write too (implications do not chain)' do
      # has_permission? only expands sources present in the role's EXPLICIT keys,
      # so a legacy role holding just ai_agents.create must name execute directly —
      # it can never reach it by hopping through the implied coarse ai_agents.write.
      assign(user, role_with('ai_agents.create'))
      expect(user.has_permission?('ai_agent_processor.execute')).to be(true)
      expect(user.all_permissions).to include('ai_agent_processor.execute')
    end

    it 'still implies the coarse write from the granular one (EVO-2127 intact)' do
      # The two implication maps collide on ai_agents.create as a source. A plain
      # Hash#merge would drop the coarse write; this locks the concatenation.
      assign(user, role_with('ai_agents.create'))
      expect(user.has_permission?('ai_agents.write')).to be(true)
      expect(user.has_permission?('ai_agent_processor.execute')).to be(true)
    end

    it 'does NOT imply execute from a read-only grant' do
      assign(user, role_with('ai_agents.read'))
      expect(user.has_permission?('ai_agent_processor.execute')).to be(false)
      expect(user.all_permissions).not_to include('ai_agent_processor.execute')
    end

    it 'does NOT imply the other system actions of the processor' do
      assign(user, role_with('ai_agents.write'))
      expect(user.has_permission?('ai_agent_processor.read')).to be(false)
      expect(user.has_permission?('ai_agent_processor.stream')).to be(false)
    end

    it 'does not leak execute to a write on an unrelated resource' do
      assign(user, role_with('contacts.create'))
      expect(user.has_permission?('ai_agent_processor.execute')).to be(false)
    end

    it 'never persists the implied system key onto the role' do
      role = role_with('ai_agents.write')
      assign(user, role)
      expect(role.role_permissions_actions.pluck(:permission_key))
        .not_to include('ai_agent_processor.execute')
    end
  end
end

RSpec.describe ResourceActionsConfig, type: :model do
  describe '.valid_permission? for the new keys' do
    it 'recognises users.manage' do
      expect(described_class.valid_permission?('users.manage')).to be(true)
    end

    it 'recognises conversations.read_all' do
      expect(described_class.valid_permission?('conversations.read_all')).to be(true)
    end

    it 'still rejects a bogus key' do
      expect(described_class.valid_permission?('users.does_not_exist')).to be(false)
    end
  end
end
