# frozen_string_literal: true

require 'rails_helper'

# Regression spec for CRM-972: profile/avatar updates must invalidate the token cache
# so changes reflect immediately in /api/v1/auth/validate without requiring a new login.
RSpec.describe 'PUT /api/v1/profile — cache invalidation (CRM-972)', type: :request do
  let(:password) { 'Test123!@' }

  before do
    # Bypass authorization checks for this spec — focus is on cache invalidation
    allow_any_instance_of(Api::V1::ProfilesController).to receive(:check_authorization).and_return(true)
  end

  def create_user
    User.create!(
      name: 'Original Name',
      email: "profile-spec-#{SecureRandom.hex(4)}@example.com",
      password: password,
      password_confirmation: password,
      confirmed_at: Time.current
    )
  end

  def bearer_token_for(user)
    app = OauthApplication.first || OauthApplication.create!(
      name: 'Profiles Spec App', redirect_uri: 'urn:ietf:wg:oauth:2.0:oob', scopes: 'public'
    )
    Doorkeeper::AccessToken.create!(
      application: app, resource_owner_id: user.id, scopes: 'public', expires_in: 2.hours
    )
  end

  def api_token_for(user)
    AccessToken.create!(owner: user, name: 'profiles-spec-token', scopes: 'default')
  end

  describe 'name update invalidates cache' do
    it 'reflects name change in validate without new login' do
      user = create_user
      token = api_token_for(user)
      headers = { 'api_access_token' => token.token }

      # 1. Validate the user (prime the cache)
      post '/api/v1/auth/validate', headers: headers
      expect(response).to have_http_status(:ok)
      original_name = response.parsed_body.dig('data', 'user', 'name')
      expect(original_name).to eq('Original Name')

      # 2. Update the name
      new_name = 'Updated Name CRM972'
      put '/api/v1/profile',
          params: { profile: { name: new_name } },
          headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'name')).to eq(new_name)

      # 3. Validate again with the SAME token — cache should be invalidated
      post '/api/v1/auth/validate', headers: headers
      expect(response).to have_http_status(:ok)
      cached_name = response.parsed_body.dig('data', 'user', 'name')
      expect(cached_name).to eq(new_name), 'cache was not invalidated after profile update'
    end
  end

  describe 'avatar update invalidates cache' do
    it 'reflects avatar change in validate without new login' do
      user = create_user
      token = api_token_for(user)
      headers = { 'api_access_token' => token.token }
      file = fixture_file_upload('spec/fixtures/avatar1.png', 'image/png')

      # 1. Validate initial state
      post '/api/v1/auth/validate', headers: headers
      expect(response).to have_http_status(:ok)

      # 2. Upload avatar
      put '/api/v1/profile/avatar',
          params: { avatar: file },
          headers: headers
      expect(response).to have_http_status(:ok)
      avatar_url = response.parsed_body.dig('data', 'avatar_url')
      expect(avatar_url).to be_present

      # 3. Validate again with the SAME token — cache should show the avatar
      post '/api/v1/auth/validate', headers: headers
      expect(response).to have_http_status(:ok)
      cached_avatar = response.parsed_body.dig('data', 'user', 'avatar_url')
      expect(cached_avatar).to eq(avatar_url), 'cache was not invalidated after avatar update'
    end
  end

  describe 'name + avatar update invalidates cache' do
    it 'reflects both changes in validate without new login' do
      user = create_user
      token = api_token_for(user)
      headers = { 'api_access_token' => token.token }
      file = fixture_file_upload('spec/fixtures/avatar1.png', 'image/png')

      # 1. Update both name and avatar
      new_name = 'Updated Both CRM972'
      put '/api/v1/profile',
          params: { profile: { name: new_name, avatar: file } },
          headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'name')).to eq(new_name)

      # 2. Validate with the SAME token — cache should reflect both changes
      post '/api/v1/auth/validate', headers: headers
      expect(response).to have_http_status(:ok)
      cached_name = response.parsed_body.dig('data', 'user', 'name')
      cached_avatar = response.parsed_body.dig('data', 'user', 'avatar_url')

      expect(cached_name).to eq(new_name), 'cache was not invalidated after name update'
      expect(cached_avatar).to be_present, 'avatar_url should be present after avatar update'
    end
  end
end
