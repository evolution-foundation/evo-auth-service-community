# frozen_string_literal: true

require 'rails_helper'

# EVO-2127 end-to-end. The role editor now saves the coarse `ai_agents.write`, so
# PUT /api/v1/roles/:id/bulk_update_permissions must:
#   * accept it (AC3 — no 422: `write` is in the catalog now), and
#   * let a delegated (non-super_admin) admin who holds the granular write grant it
#     (AC4 — no 403: ai_agents.create implies ai_agents.write in all_permissions).
# The two gates (422 unknown-key, 403 grant-what-you-don't-hold) must still bite.
RSpec.describe 'PUT /api/v1/roles/:id/bulk_update_permissions (EVO-2127 coarse write)', type: :request do
  let(:password) { 'Test123!@' }

  def build_user(name)
    User.create!(
      name: name,
      email: "#{name.parameterize}-#{SecureRandom.hex(4)}@example.com",
      password: password,
      password_confirmation: password,
      confirmed_at: Time.current
    )
  end

  def role_with(*permission_keys, type: 'account', key: "role-#{SecureRandom.hex(4)}")
    role = Role.create!(key: key, name: key.titleize, type: type, system: false)
    permission_keys.each { |pk| role.role_permissions_actions.create!(permission_key: pk) }
    role
  end

  def headers_for(user)
    token = AccessToken.create!(owner: user, name: "tk-#{SecureRandom.hex(3)}", scopes: 'default')
    { 'api_access_token' => token.token, 'Host' => 'localhost' }
  end

  def bulk_update(role, keys, as_user)
    put "/api/v1/roles/#{role.id}/bulk_update_permissions",
        params: { permission_keys: keys },
        headers: headers_for(as_user),
        as: :json
  end

  before do
    allow(Licensing::Runtime).to receive(:context).and_return(
      instance_double(Licensing::RuntimeContext, active?: true, track_message: nil)
    )
  end

  # A delegated admin: can edit roles AND holds the granular AI-agent write.
  let(:delegated_admin) do
    build_user('Delegated Admin').tap do |u|
      UserRole.create!(user: u, role: role_with('roles.bulk_update_permissions', 'ai_agents.create'))
    end
  end
  let(:target_role) { role_with('ai_agents.read', type: 'account') }

  it 'accepts the coarse ai_agents.write without 422/403 and persists it additively (AC3/AC4)' do
    bulk_update(target_role, %w[ai_agents.read ai_agents.create ai_agents.write], delegated_admin)

    expect(response).to have_http_status(:ok)
    expect(target_role.reload.permission_keys).to include('ai_agents.write', 'ai_agents.create')
  end

  it '403s a delegated admin who does NOT hold the granular write (403 gate intact)' do
    weak_admin = build_user('Weak Admin').tap do |u|
      UserRole.create!(user: u, role: role_with('roles.bulk_update_permissions'))
    end

    bulk_update(target_role, %w[ai_agents.read ai_agents.write], weak_admin)

    expect(response).to have_http_status(:forbidden)
    expect(target_role.reload.permission_keys).not_to include('ai_agents.write')
  end

  it '422s an unknown permission key (valid_permission? gate intact)' do
    bulk_update(target_role, %w[ai_agents.bogus_action], delegated_admin)

    expect(response).to have_http_status(:unprocessable_entity)
  end

  # The coarse write has to come back OUT of the DB too. The editor's Write
  # checkbox is the only way to revoke it, and it revokes by omitting the key from
  # the payload — so a save without `ai_agents.write` must delete the row. This is
  # what a locked (implied_by) coarse write would have silently prevented: the
  # front drops locked keys from the group the checkbox controls, so the key would
  # be added once and never removed again.
  it 'revokes the coarse write when the payload omits it' do
    role = role_with('ai_agents.read', 'ai_agents.create', 'ai_agents.write')

    bulk_update(role, %w[ai_agents.read], delegated_admin)

    expect(response).to have_http_status(:ok)
    expect(role.reload.permission_keys).to eq(['ai_agents.read'])
    expect(role.permission_keys).not_to include('ai_agents.write')
  end

  # A delegated admin editing a PRE-EXISTING role: the editor re-sends the whole
  # permission set, so every coarse write the role earns is a NEW key and lands in
  # `granted`. The admin below writes to contacts, not to AI agents — but the role
  # already holds ai_agents.create, so ai_agents.write confers nothing new on it
  # and must not 403. Without the implied-by-target exemption, this admin could no
  # longer save ANY role that writes outside their own scope.
  it 'lets a delegated admin save a role whose coarse write they do not hold themselves' do
    contacts_admin = build_user('Contacts Admin').tap do |u|
      UserRole.create!(user: u, role: role_with('roles.bulk_update_permissions', 'contacts.create'))
    end
    legacy_role = role_with('ai_agents.read', 'ai_agents.create', 'contacts.create')

    expect(contacts_admin.has_permission?('ai_agents.write')).to be(false) # the caller really lacks it

    bulk_update(legacy_role, %w[ai_agents.read ai_agents.create ai_agents.write contacts.create contacts.write],
                contacts_admin)

    expect(response).to have_http_status(:ok)
    expect(legacy_role.reload.permission_keys).to include('ai_agents.write', 'contacts.write')
  end

  # The exemption is narrow: it only pardons a key the TARGET SET itself implies.
  # Granting the granular write that would imply it is still a real escalation.
  it 'still 403s a delegated admin granting a granular write they do not hold' do
    contacts_admin = build_user('Contacts Admin 2').tap do |u|
      UserRole.create!(user: u, role: role_with('roles.bulk_update_permissions', 'contacts.create'))
    end

    bulk_update(target_role, %w[ai_agents.read ai_agents.create ai_agents.write], contacts_admin)

    expect(response).to have_http_status(:forbidden)
    expect(target_role.reload.permission_keys).not_to include('ai_agents.create', 'ai_agents.write')
  end
end
