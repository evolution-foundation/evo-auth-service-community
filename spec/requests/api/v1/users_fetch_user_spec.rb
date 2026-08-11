# frozen_string_literal: true

require 'rails_helper'

# Regression guard for Api::V1::UsersController#fetch_user, the before_action
# that loads @user for every member action. It called a `users` helper that had
# already been deleted, so update/destroy/check_permission/role raised NameError
# and answered 500 — and the CRM, which calls check_permission on every screen,
# 403'd across the board behind a fail-close gateway.
#
# The RBAC specs cover WHO may call these routes. This one covers that the
# target user is resolved at all, on the route the CRM actually hits: asserting
# the answer describes the user in the path, not the caller, fails both on a
# NameError and on a silent fallback to current_user.
RSpec.describe 'UsersController fetch_user target resolution', type: :request do
  # db:schema:load leaves `roles` empty — the system roles are created by data
  # migrations, which a schema-loaded database never runs.
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

    # The caller (agent) does not hold users.manage and the target (super_admin)
    # does: one shared example would pass on the caller's own grants, so the two
    # verdicts are asserted against each other.
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
