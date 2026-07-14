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
end
