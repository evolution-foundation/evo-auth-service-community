# frozen_string_literal: true

require 'rails_helper'

# Exercises the bracket param shape the Users list screen actually sends
# (filters[0][attribute_key]=...) end to end: parsing, auth gate and pagination.
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

  def make_user(name)
    User.create!(name: name, email: "#{name.parameterize}-#{SecureRandom.hex(3)}@example.com",
                 password: password, password_confirmation: password, confirmed_at: Time.current)
  end

  let!(:alice) { make_user('Alice Silva') }
  let!(:bob) { make_user('Bob Souza') }

  before { admin_user }

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

  # The service spec covers the SQL; these cover the controller forwarding the
  # params. The table is not empty, so each example asserts on the relative
  # order of its own three fixtures.
  describe 'sort and order' do
    let(:own_names) { ['Alice Silva', 'Bob Souza', 'Zadmin User'] }

    def own_order
      response_names.select { |name| own_names.include?(name) }
    end

    def list(params = {})
      get '/api/v1/users', params: { 'per_page' => 100 }.merge(params), headers: headers
    end

    it 'defaults to name ascending when no sort is given' do
      list

      expect(response).to have_http_status(:ok)
      expect(own_order).to eq(['Alice Silva', 'Bob Souza', 'Zadmin User'])
    end

    it 'honors sort=name with order=desc' do
      list('sort' => 'name', 'order' => 'desc')

      expect(response).to have_http_status(:ok)
      expect(own_order).to eq(['Zadmin User', 'Bob Souza', 'Alice Silva'])
    end

    it 'honors sort=role, ordering by the role name and not by the user name' do
      UserRole.assign_role_to_user(alice, Role.create!(key: "zeta-#{SecureRandom.hex(4)}", name: 'Zeta',
                                                       type: 'account', system: false))
      UserRole.assign_role_to_user(bob, Role.create!(key: "alpha-#{SecureRandom.hex(4)}", name: 'Alpha',
                                                     type: 'account', system: false))

      list('sort' => 'role', 'order' => 'asc')

      # Alpha (Bob) < Reader (the admin's role) < Zeta (Alice) — the reverse of
      # the name ordering, so a dropped sort param cannot pass this.
      expect(response).to have_http_status(:ok)
      expect(own_order).to eq(['Bob Souza', 'Zadmin User', 'Alice Silva'])
    end

    it 'falls back to name ascending for a sort key outside the whitelist' do
      list('sort' => 'encrypted_password')

      expect(response).to have_http_status(:ok)
      expect(own_order).to eq(['Alice Silva', 'Bob Souza', 'Zadmin User'])
    end
  end
end
