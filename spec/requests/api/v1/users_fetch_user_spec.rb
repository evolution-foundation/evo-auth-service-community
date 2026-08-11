# frozen_string_literal: true

require 'rails_helper'

# The member actions must answer for the user in the path, not the caller. The
# RBAC specs cover who may call them; these cover that the target resolves.
RSpec.describe 'UsersController fetch_user target resolution', type: :request do
  # Roles come from data migrations, which a schema-loaded database never runs.
  before { load Rails.root.join('db/seeds/rbac.rb') }

  let(:password) { 'Test123!@' }
  let(:agent_role) { Role.find_by!(key: 'agent') }
  let(:admin_role) { Role.find_by!(key: 'super_admin') }

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

  let(:agent_user) { build_user('Agent User', role: agent_role) }
  let(:admin_user) { build_user('Admin User', role: admin_role) }

  describe 'POST /api/v1/users/:id/check_permission' do
    it 'answers for the user in the path, not for the caller' do
      post "/api/v1/users/#{admin_user.id}/check_permission",
           params: { permission_key: 'users.manage' },
           headers: headers_for(agent_user),
           as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'role', 'key')).to eq('super_admin')
    end

    it 'resolves the target grant rather than the caller grant' do
      post "/api/v1/users/#{admin_user.id}/check_permission",
           params: { permission_key: 'users.manage' },
           headers: headers_for(agent_user),
           as: :json
      target_verdict = response.parsed_body.dig('data', 'has_permission')

      post "/api/v1/users/#{agent_user.id}/check_permission",
           params: { permission_key: 'users.manage' },
           headers: headers_for(agent_user),
           as: :json
      caller_verdict = response.parsed_body.dig('data', 'has_permission')

      expect(target_verdict).to be(true)
      expect(caller_verdict).to be(false)
    end
  end

  describe 'GET /api/v1/users/:id/role' do
    it 'returns the role of the user in the path' do
      get "/api/v1/users/#{admin_user.id}/role",
          headers: headers_for(agent_user),
          as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'role', 'key')).to eq('super_admin')
    end
  end
end
