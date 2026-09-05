# frozen_string_literal: true

require 'rails_helper'

# CRM-535 — payloads that describe OTHER users never carry pubsub_token (the
# RoomChannel subscription credential), ui_settings, custom_attributes or MFA
# state. The user's own payloads (/me, self update) keep them.
RSpec.describe 'Users directory serialization (CRM-535)', type: :request do
  before { load Rails.root.join('db/seeds/rbac.rb') }

  let(:password) { 'Test123!@' }
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

  let(:admin_user) { build_user('Admin User', role: admin_role) }
  let!(:other_user) { build_user('Other User') }

  PRIVATE_KEYS = %w[pubsub_token ui_settings custom_attributes mfa_enabled mfa_setup_incomplete].freeze
  DIRECTORY_KEYS = %w[id name email role availability avatar_url confirmed created_at].freeze

  def body
    JSON.parse(response.body)
  end

  describe 'GET /api/v1/users' do
    it 'lists the directory fields and none of the private ones' do
      get '/api/v1/users', headers: headers_for(admin_user)

      expect(response).to have_http_status(:ok)
      users = body['data']
      expect(users.map { |u| u['id'] }).to include(other_user.id, admin_user.id)
      users.each do |user|
        expect(user.keys).to include(*DIRECTORY_KEYS)
        expect(user.keys).not_to include(*PRIVATE_KEYS)
      end
    end
  end

  describe 'GET /api/v1/auth/me' do
    it 'still returns the caller their own pubsub_token' do
      get '/api/v1/auth/me', headers: headers_for(admin_user)

      expect(response).to have_http_status(:ok)
      expect(body.dig('data', 'user', 'pubsub_token')).to eq(admin_user.pubsub_token)
    end
  end

  describe 'PATCH /api/v1/users/:id' do
    it 'returns the pubsub_token when the target is the caller' do
      patch "/api/v1/users/#{admin_user.id}", params: { name: 'Renamed Admin' },
                                               headers: headers_for(admin_user), as: :json

      expect(response).to have_http_status(:ok)
      expect(body.dig('data', 'user', 'pubsub_token')).to eq(admin_user.pubsub_token)
    end

    it 'omits the private fields when the target is another user' do
      patch "/api/v1/users/#{other_user.id}", params: { name: 'Renamed Other' },
                                               headers: headers_for(admin_user), as: :json

      expect(response).to have_http_status(:ok)
      expect(body.dig('data', 'user', 'name')).to eq('Renamed Other')
      expect(body.dig('data', 'user').keys).not_to include(*PRIVATE_KEYS)
    end
  end

  describe 'POST /api/v1/users' do
    it 'omits the private fields of the user it creates' do
      post '/api/v1/users',
           params: { email: "new-#{SecureRandom.hex(4)}@example.com", name: 'New Agent', password: password },
           headers: headers_for(admin_user), as: :json

      expect(response).to have_http_status(:created)
      expect(body.dig('data', 'user', 'id')).to be_present
      expect(body.dig('data', 'user').keys).not_to include(*PRIVATE_KEYS)
    end
  end
end
