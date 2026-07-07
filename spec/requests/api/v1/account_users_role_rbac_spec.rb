# frozen_string_literal: true

require 'rails_helper'

# PATCH /api/v1/account enforces accounts.update (which the seeded agent role
# no longer holds), and GET /api/v1/users/:id/role enforces users.read (it was
# absent from the authorization map, falling through open).
RSpec.describe 'Account update and users role RBAC', type: :request do
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
  let(:roleless_user) { build_user('Roleless User') }

  before do
    allow(Licensing::Runtime).to receive(:context).and_return(
      instance_double(Licensing::RuntimeContext, active?: true, track_message: nil)
    )

    RuntimeConfig.set('account', {
      'id' => 1,
      'name' => 'Acme',
      'settings' => { 'mask_contact_pii' => true },
      'custom_attributes' => {}
    })
  end

  describe 'PATCH /api/v1/account' do
    it 'denies the seeded agent (no accounts.update) and keeps the account intact' do
      patch '/api/v1/account',
            params: { account: { name: 'Hijacked' } },
            headers: headers_for(agent_user),
            as: :json

      expect(response).to have_http_status(:forbidden)
      expect(RuntimeConfig.account['name']).to eq('Acme')
    end

    it 'denies a user with no grants' do
      patch '/api/v1/account',
            params: { account: { name: 'Hijacked' } },
            headers: headers_for(roleless_user),
            as: :json

      expect(response).to have_http_status(:forbidden)
      expect(RuntimeConfig.account['name']).to eq('Acme')
    end

    it 'updates for an admin holding accounts.update' do
      patch '/api/v1/account',
            params: { account: { name: 'Renamed' } },
            headers: headers_for(admin_user),
            as: :json

      expect(response).to have_http_status(:ok)
      expect(RuntimeConfig.account['name']).to eq('Renamed')
    end
  end

  describe 'GET /api/v1/users/:id/role' do
    it 'denies a user without users.read' do
      get "/api/v1/users/#{admin_user.id}/role", headers: headers_for(roleless_user), as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "returns another user's role for a holder of users.read (agent)" do
      get "/api/v1/users/#{admin_user.id}/role", headers: headers_for(agent_user), as: :json

      expect(response).to have_http_status(:ok)
    end
  end
end
