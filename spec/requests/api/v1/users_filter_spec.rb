# frozen_string_literal: true

require 'rails_helper'

# EVO-1947 (Fase A): GET /api/v1/users must honor the advanced-filter payload
# the Users list screen sends in bracket format
# (filters[0][attribute_key]=...&filters[0][filter_operator]=...). Before this
# card the controller ignored it (@users = users). This request spec exercises
# the real param shape end to end (parsing + auth gate + pagination).
RSpec.describe 'GET /api/v1/users — advanced filtering (EVO-1947)', type: :request do
  let(:password) { 'Test123!@' }

  let(:reader_role) do
    role = Role.create!(key: "reader-#{SecureRandom.hex(4)}", name: 'Reader', type: 'account', system: false)
    role.role_permissions_actions.create!(permission_key: 'users.read')
    role
  end

  let(:admin_user) do
    user = User.create!(
      name: 'Zadmin User',
      email: "admin-#{SecureRandom.hex(4)}@example.com",
      password: password,
      password_confirmation: password,
      confirmed_at: Time.current
    )
    UserRole.assign_role_to_user(user, reader_role)
    user
  end

  let(:token) { AccessToken.create!(owner: admin_user, name: 'admin-token', scopes: 'default') }
  let(:headers) { { 'api_access_token' => token.token, 'Host' => 'localhost' } }

  before do
    User.create!(name: 'Alice Silva', email: "alice-#{SecureRandom.hex(3)}@example.com",
                 password: password, password_confirmation: password, confirmed_at: Time.current)
    User.create!(name: 'Bob Souza', email: "bob-#{SecureRandom.hex(3)}@example.com",
                 password: password, password_confirmation: password, confirmed_at: Time.current)
    admin_user
  end

  def response_names
    JSON.parse(response.body)['data'].map { |user| user['name'] }
  end

  it 'honors a name filter sent in bracket param format' do
    get '/api/v1/users',
        params: { 'filters' => { '0' => { 'attribute_key' => 'name', 'filter_operator' => 'contains', 'values' => 'silva' } } },
        headers: headers

    expect(response).to have_http_status(:ok)
    expect(response_names).to include('Alice Silva')
    expect(response_names).not_to include('Bob Souza')
  end

  it 'honors the q search param' do
    get '/api/v1/users', params: { 'q' => 'silva' }, headers: headers

    expect(response).to have_http_status(:ok)
    expect(response_names).to include('Alice Silva')
    expect(response_names).not_to include('Bob Souza')
  end

  it 'returns every user when no filter is sent' do
    get '/api/v1/users', headers: headers

    expect(response).to have_http_status(:ok)
    expect(response_names).to include('Alice Silva', 'Bob Souza')
  end
end
