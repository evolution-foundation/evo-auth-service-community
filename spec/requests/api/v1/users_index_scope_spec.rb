# frozen_string_literal: true

require 'rails_helper'

# `users_index_scope` is the seam a deployment overrides to restrict the
# directory. These examples pin the contract: whatever it returns is the outer
# bound of the list, of the search and of the pagination total.
RSpec.describe 'GET /api/v1/users — users_index_scope extension point', type: :request do
  let(:password) { 'Test123!@' }

  let(:reader_role) do
    role = Role.create!(key: "reader-#{SecureRandom.hex(4)}", name: 'Reader', type: 'account', system: false)
    role.role_permissions_actions.create!(permission_key: 'users.read')
    role
  end

  def make_user(name)
    User.create!(name: name, email: "#{name.parameterize}-#{SecureRandom.hex(3)}@example.com",
                 password: password, password_confirmation: password, confirmed_at: Time.current)
  end

  let!(:caller) { make_user('Caller Silva').tap { |user| UserRole.assign_role_to_user(user, reader_role) } }
  let!(:visible) { make_user('Visible Silva') }
  let!(:hidden) { make_user('Hidden Silva') }

  let(:token) { AccessToken.create!(owner: caller, name: 'caller-token', scopes: 'default') }
  let(:headers) { { 'api_access_token' => token.token, 'Host' => 'localhost' } }

  def body
    JSON.parse(response.body)
  end

  def response_ids
    body['data'].map { |user| user['id'] }
  end

  context 'with the default scope' do
    it 'lists the whole table' do
      get '/api/v1/users', params: { 'per_page' => 100 }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(response_ids).to include(caller.id, visible.id, hidden.id)
    end
  end

  context 'when a deployment narrows the scope' do
    before do
      allow_any_instance_of(Api::V1::UsersController)
        .to receive(:users_index_scope).and_return(User.where(id: [caller.id, visible.id]))
    end

    it 'lists only users inside the scope' do
      get '/api/v1/users', params: { 'per_page' => 100 }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(response_ids).to contain_exactly(caller.id, visible.id)
    end

    it 'keeps the search inside the scope' do
      get '/api/v1/users', params: { 'q' => 'silva', 'per_page' => 100 }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(response_ids).to contain_exactly(caller.id, visible.id)
    end

    it 'reports the pagination total of the scope, not of the table' do
      get '/api/v1/users', params: { 'per_page' => 1 }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(body.dig('meta', 'pagination', 'total')).to eq(2)
    end
  end
end
