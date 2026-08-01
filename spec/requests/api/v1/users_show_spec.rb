# frozen_string_literal: true

require 'rails_helper'

# Regression for EVO-1947: the refactor that introduced Users::FilterService
# removed the private `users` helper from Api::V1::UsersController, but
# fetch_user (before_action for show/update/check_permission) still called it.
# Every :id route then raised NameError -> 500; callers that gate on
# check_permission treat that 500 as "denied", locking every consumer out.
RSpec.describe 'GET /api/v1/users/:id (EVO-1947 fetch_user regression)', type: :request do
  let(:password) { 'Test123!@' }

  let(:reader_role) do
    role = Role.create!(key: "reader-#{SecureRandom.hex(4)}", name: 'Reader', type: 'account', system: false)
    role.role_permissions_actions.create!(permission_key: 'users.read')
    role
  end

  let(:current_user) do
    user = User.create!(
      name: 'Requester User',
      email: "requester-#{SecureRandom.hex(4)}@example.com",
      password: password,
      password_confirmation: password,
      confirmed_at: Time.current
    )
    UserRole.assign_role_to_user(user, reader_role)
    user
  end

  let(:target) do
    User.create!(
      name: 'Target User',
      email: "target-#{SecureRandom.hex(4)}@example.com",
      password: password,
      password_confirmation: password,
      confirmed_at: Time.current
    )
  end

  let(:token) { AccessToken.create!(owner: current_user, name: 'req-token', scopes: 'default') }
  let(:headers) { { 'api_access_token' => token.token, 'Host' => 'localhost' } }

  it 'resolves the target user instead of raising NameError' do
    get "/api/v1/users/#{target.id}", headers: headers

    expect(response).to have_http_status(:ok)
  end
end
