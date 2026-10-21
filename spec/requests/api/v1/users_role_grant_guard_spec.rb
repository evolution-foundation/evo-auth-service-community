# frozen_string_literal: true

require 'rails_helper'

# users.manage administers agents, not the installation owner: granting,
# demoting or deleting a super_admin takes a super_admin; a service token
# carries no user and never qualifies.
RSpec.describe 'Users role-grant guard (super_admin rank)', type: :request do
  before { load Rails.root.join('db/seeds/rbac.rb') }

  let(:password) { 'Test123!@' }
  let(:super_admin_role) { Role.find_by!(key: 'super_admin') }
  let(:owner_role) { Role.find_by!(key: 'account_owner') }
  let(:agent_role) { Role.find_by!(key: 'agent') }

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

  def service_headers
    { 'X-Service-Token' => 'service-token-probe', 'Host' => 'localhost' }
  end

  def with_service_token
    original = ENV['EVOAI_AUTH_API_TOKEN']
    ENV['EVOAI_AUTH_API_TOKEN'] = 'service-token-probe'
    yield
  ensure
    ENV['EVOAI_AUTH_API_TOKEN'] = original
  end

  def role_keys_of(user)
    user.reload.roles.pluck(:key)
  end

  def new_email
    "new-#{SecureRandom.hex(4)}@example.com"
  end

  let(:super_admin) { build_user('Root Admin', role: super_admin_role) }
  let(:owner) { build_user('Account Owner', role: owner_role) }
  let(:target) { build_user('Target Agent', role: agent_role) }

  describe 'granting super_admin' do
    it 'refuses an account_owner promoting another user' do
      patch "/api/v1/users/#{target.id}", params: { role: 'super_admin' }, headers: headers_for(owner), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig('error', 'message')).to include('cannot be granted')
      expect(role_keys_of(target)).to eq(%w[agent])
    end

    it 'refuses an account_owner promoting themselves' do
      patch "/api/v1/users/#{owner.id}", params: { role: 'super_admin' }, headers: headers_for(owner), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(role_keys_of(owner)).to eq(%w[account_owner])
    end

    it 'refuses super_admin on create' do
      email = new_email
      post '/api/v1/users', params: { email: email, name: 'New', password: password, role: 'super_admin' },
                            headers: headers_for(owner), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(User.find_by(email: email)).to be_nil
    end

    it 'refuses super_admin on bulk_create' do
      email = new_email
      post '/api/v1/users/bulk_create', params: { emails: [ email ], role: 'super_admin' },
                                        headers: headers_for(owner), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(User.find_by(email: email)).to be_nil
    end

    it 'lets a super_admin grant super_admin' do
      patch "/api/v1/users/#{target.id}", params: { role: 'super_admin' }, headers: headers_for(super_admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(role_keys_of(target)).to eq(%w[super_admin])
    end

    it 'still lets an account_owner grant account_owner' do
      patch "/api/v1/users/#{target.id}", params: { role: 'account_owner' }, headers: headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect(role_keys_of(target)).to eq(%w[account_owner])
    end
  end

  describe 'service token' do
    it 'never grants super_admin' do
      email = new_email
      with_service_token do
        post '/api/v1/users', params: { email: email, name: 'New', password: password, role: 'super_admin' },
                              headers: service_headers, as: :json
      end

      expect(response).to have_http_status(:forbidden)
      expect(User.find_by(email: email)).to be_nil
    end

    it 'keeps creating agents' do
      email = new_email
      with_service_token do
        post '/api/v1/users', params: { email: email, name: 'New', password: password, role: 'agent' },
                              headers: service_headers, as: :json
      end

      expect(response).to have_http_status(:created)
      expect(role_keys_of(User.find_by!(email: email))).to eq(%w[agent])
    end

    it 'cannot demote a super_admin' do
      with_service_token do
        patch "/api/v1/users/#{super_admin.id}", params: { role: 'agent' }, headers: service_headers, as: :json
      end

      expect(response).to have_http_status(:forbidden)
      expect(role_keys_of(super_admin)).to eq(%w[super_admin])
    end

    it 'cannot delete a super_admin' do
      with_service_token do
        delete "/api/v1/users/#{super_admin.id}", headers: service_headers, as: :json
      end

      expect(response).to have_http_status(:forbidden)
      expect(User.exists?(super_admin.id)).to be(true)
    end

    it 'still deletes an agent (no current_user to self-check against)' do
      with_service_token do
        delete "/api/v1/users/#{target.id}", headers: service_headers, as: :json
      end

      expect(response).to have_http_status(:ok)
      expect(User.exists?(target.id)).to be(false)
    end
  end

  describe 'a super_admin as the target' do
    it 'is not demoted by an account_owner' do
      patch "/api/v1/users/#{super_admin.id}", params: { role: 'agent' }, headers: headers_for(owner), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig('error', 'message')).to include('super_admin')
      expect(role_keys_of(super_admin)).to eq(%w[super_admin])
    end

    it 'is not deleted by an account_owner' do
      delete "/api/v1/users/#{super_admin.id}", headers: headers_for(owner), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(User.exists?(super_admin.id)).to be(true)
    end

    it 'is renamed by an account_owner resubmitting the current role (no role change)' do
      patch "/api/v1/users/#{super_admin.id}", params: { name: 'Renamed', role: 'super_admin' },
                                               headers: headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect(super_admin.reload.name).to eq('Renamed')
      expect(role_keys_of(super_admin)).to eq(%w[super_admin])
    end

    it 'is demoted by another super_admin' do
      other = build_user('Other Root', role: super_admin_role)
      patch "/api/v1/users/#{other.id}", params: { role: 'agent' }, headers: headers_for(super_admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(role_keys_of(other)).to eq(%w[agent])
    end
  end
end
