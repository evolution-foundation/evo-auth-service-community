# frozen_string_literal: true

require 'rails_helper'

# Story RBAC 4.2 (FR24) — administrative user management (create/destroy/
# bulk_create and role assignment on update) requires users.manage at the
# endpoint, mirroring the frontend Settings > Agents gate. Reads and
# self-service updates stay on the fine operational keys alone.
RSpec.describe 'Users administrative gate (users.manage)', type: :request do
  let(:password) { 'Test123!@' }
  let(:admin_role) { Role.find_by!(key: 'super_admin') }

  # Holds every fine users.* key EXCEPT users.manage — the exact profile the
  # gate must stop from administering agents.
  let(:delegated_role) do
    role = Role.create!(key: "delegate-#{SecureRandom.hex(4)}", name: 'Delegate', type: 'account')
    %w[users.read users.create users.update users.delete users.bulk_operations].each do |key|
      role.role_permissions_actions.create!(permission_key: key)
    end
    role
  end

  def build_user(name, role: nil)
    user = User.create!(
      name: name,
      email: "#{name.parameterize}-#{SecureRandom.hex(4)}@example.com",
      password: password,
      password_confirmation: password,
      confirmed_at: Time.current
    )
    UserRole.create!(user: user, role: role) if role
    user
  end

  def headers_for(user)
    token = AccessToken.create!(owner: user, name: "tk-#{SecureRandom.hex(3)}", scopes: 'default')
    { 'api_access_token' => token.token, 'Host' => 'localhost' }
  end

  let(:admin_user) { build_user('Admin User', role: admin_role) }
  let(:delegated_user) { build_user('Delegated User', role: delegated_role) }
  let(:target_user) { build_user('Target User') }

  describe 'POST /api/v1/users' do
    it 'denies a caller holding users.create but not users.manage' do
      post '/api/v1/users',
           params: { email: "new-#{SecureRandom.hex(4)}@example.com", name: 'New Agent', password: password },
           headers: headers_for(delegated_user),
           as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'creates for a caller holding users.manage' do
      email = "new-#{SecureRandom.hex(4)}@example.com"
      post '/api/v1/users',
           params: { email: email, name: 'New Agent', password: password },
           headers: headers_for(admin_user),
           as: :json

      expect(response).to have_http_status(:created).or have_http_status(:ok)
      expect(User.exists?(email: email)).to be(true)
    end
  end

  describe 'DELETE /api/v1/users/:id' do
    it 'denies a caller holding users.delete but not users.manage' do
      delete "/api/v1/users/#{target_user.id}", headers: headers_for(delegated_user)

      expect(response).to have_http_status(:forbidden)
      expect(User.exists?(target_user.id)).to be(true)
    end

    it 'deletes for a caller holding users.manage' do
      delete "/api/v1/users/#{target_user.id}", headers: headers_for(admin_user)

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'PATCH /api/v1/users/:id' do
    it 'denies a role assignment without users.manage' do
      patch "/api/v1/users/#{target_user.id}",
            params: { role: 'agent' },
            headers: headers_for(delegated_user),
            as: :json

      expect(response).to have_http_status(:forbidden)
      expect(target_user.reload.roles.pluck(:key)).not_to include('agent')
    end

    it 'still allows a plain attribute update on users.update alone (no role change)' do
      patch "/api/v1/users/#{target_user.id}",
            params: { name: 'Renamed Target' },
            headers: headers_for(delegated_user),
            as: :json

      expect(response).to have_http_status(:ok)
      expect(target_user.reload.name).to eq('Renamed Target')
    end

    it 'does not trip the gate when the submitted role is unchanged (frontend sends it always)' do
      agent = Role.find_by!(key: 'agent')
      UserRole.create!(user: target_user, role: agent)

      patch "/api/v1/users/#{target_user.id}",
            params: { name: 'Still Agent', role: 'agent' },
            headers: headers_for(delegated_user),
            as: :json

      expect(response).to have_http_status(:ok)
      expect(target_user.reload.name).to eq('Still Agent')
    end

    it 'assigns a role for a caller holding users.manage' do
      patch "/api/v1/users/#{target_user.id}",
            params: { role: 'agent' },
            headers: headers_for(admin_user),
            as: :json

      expect(response).to have_http_status(:ok)
      expect(target_user.reload.roles.pluck(:key)).to include('agent')
    end
  end

  describe 'POST /api/v1/users/bulk_create' do
    it 'denies a caller holding users.bulk_operations but not users.manage' do
      post '/api/v1/users/bulk_create',
           params: { users: [ { email: "bulk-#{SecureRandom.hex(4)}@example.com", name: 'Bulk' } ] },
           headers: headers_for(delegated_user),
           as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'denial of the BASE key on an administrative action' do
    it 'renders a single 403 (no DoubleRenderError) when users.create itself is missing' do
      agent_user = build_user('Agent User', role: Role.find_by!(key: 'agent'))

      post '/api/v1/users',
           params: { email: "x-#{SecureRandom.hex(4)}@example.com", name: 'X', password: password },
           headers: headers_for(agent_user),
           as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end
end
