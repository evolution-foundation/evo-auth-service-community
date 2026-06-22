# frozen_string_literal: true

require 'rails_helper'

# Request spec for the account_user_roles fix (tech-spec
# rbac-granular-inbox-permissions, T2.4). The endpoint feeds the "create/edit
# attendant" modal in the frontend; it used to hardcode
# Role.where(key: ['agent','account_owner']) so custom type:'account' roles
# (e.g. "Converse") never appeared and could not be assigned to attendants.
# It must now return the system roles PLUS every custom account role.
RSpec.describe 'GET /api/v1/roles/account_user_roles (EVO RBAC split T2.4)', type: :request do
  let(:password) { 'Test123!@' }

  # Seed the system roles (agent / account_owner / super_admin) with their
  # permission sets so the endpoint's authorization (roles.read on account_owner)
  # and the no-regression assertions have real data to work against.
  before do
    load Rails.root.join('db/seeds/rbac.rb')
  end

  # account_owner is seeded with roles.read, which the endpoint requires.
  let(:admin_role) { Role.find_by!(key: 'account_owner') }

  let!(:custom_account_role) do
    Role.create!(key: "converse-#{SecureRandom.hex(4)}", name: "Converse #{SecureRandom.hex(2)}",
                 type: 'account', system: false)
  end

  let(:admin_user) do
    user = User.create!(
      name: 'Owner User',
      email: "owner-#{SecureRandom.hex(4)}@example.com",
      password: password,
      password_confirmation: password,
      confirmed_at: Time.current
    )
    UserRole.create!(user: user, role: admin_role)
    user
  end

  let(:token) { AccessToken.create!(owner: admin_user, name: 'owner-token', scopes: 'default') }
  let(:headers) { { 'api_access_token' => token.token, 'Host' => 'localhost' } }

  before do
    allow(Licensing::Runtime).to receive(:context).and_return(
      instance_double(Licensing::RuntimeContext, active?: true, track_message: nil)
    )
  end

  def returned_keys
    JSON.parse(response.body).dig('data').map { |r| r['key'] }
  end

  it 'returns 200' do
    get '/api/v1/roles/account_user_roles', headers: headers
    expect(response).to have_http_status(:ok)
  end

  it 'includes the system agent and account_owner roles (no regression)' do
    get '/api/v1/roles/account_user_roles', headers: headers
    expect(returned_keys).to include('agent', 'account_owner')
  end

  it 'includes a custom type:account role (AC8 — the bug fix)' do
    get '/api/v1/roles/account_user_roles', headers: headers
    expect(returned_keys).to include(custom_account_role.key)
  end

  it 'does NOT include user-type roles other than account_owner (e.g. super_admin)' do
    get '/api/v1/roles/account_user_roles', headers: headers
    expect(returned_keys).not_to include('super_admin')
  end
end
