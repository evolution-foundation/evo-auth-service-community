# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'PUT /api/v1/profile — token cache invalidation', type: :request do
  let(:password) { 'Test123!@' }
  let(:user) do
    User.create!(
      name: 'Original Name',
      email: "profile-spec-#{SecureRandom.hex(4)}@example.com",
      password: password,
      password_confirmation: password,
      confirmed_at: Time.current
    )
  end

  before do
    allow_any_instance_of(Api::V1::ProfilesController).to receive(:check_authorization).and_return(true)
  end

  def api_token_headers
    { 'api_access_token' => AccessToken.create!(owner: user, name: 'profiles-spec-token', scopes: 'default').token }
  end

  def bearer_headers
    app = OauthApplication.first || OauthApplication.create!(
      name: 'Profiles Spec App', redirect_uri: 'urn:ietf:wg:oauth:2.0:oob', scopes: 'public'
    )
    token = Doorkeeper::AccessToken.create!(application: app, resource_owner_id: user.id, scopes: 'public', expires_in: 2.hours)
    { 'Authorization' => "Bearer #{token.token}" }
  end

  def account_token_headers
    token = AccessToken.create!(owner: user, name: 'account-spec-token', scopes: 'default')
    token.update_columns(owner_type: 'Account', owner_id: SecureRandom.uuid, issued_id: user.id)
    { 'api_access_token' => token.token }
  end

  def validated_user(headers)
    post '/api/v1/auth/validate', headers: headers
    expect(response).to have_http_status(:ok)
    response.parsed_body.dig('data', 'user')
  end

  def avatar_file
    fixture_file_upload('spec/fixtures/avatar1.png', 'image/png')
  end

  it 'returns the new name to the same API token right after the update' do
    headers = api_token_headers
    expect(validated_user(headers)['name']).to eq('Original Name')

    put '/api/v1/profile', params: { profile: { name: 'Updated Name' } }, headers: headers
    expect(response).to have_http_status(:ok)

    expect(validated_user(headers)['name']).to eq('Updated Name')
  end

  it 'returns the new name to the same session (bearer) token right after the update' do
    headers = bearer_headers
    expect(validated_user(headers)['name']).to eq('Original Name')

    put '/api/v1/profile', params: { profile: { name: 'Updated Name' } }, headers: headers
    expect(response).to have_http_status(:ok)

    expect(validated_user(headers)['name']).to eq('Updated Name')
  end

  it 'returns the new name to an account token issued to the user' do
    headers = account_token_headers
    expect(validated_user(headers)['name']).to eq('Original Name')

    put '/api/v1/profile', params: { profile: { name: 'Updated Name' } }, headers: bearer_headers
    expect(response).to have_http_status(:ok)

    expect(validated_user(headers)['name']).to eq('Updated Name')
  end

  it 'returns the new avatar right after PUT /api/v1/profile/avatar' do
    headers = api_token_headers
    expect(validated_user(headers)['avatar_url']).to be_blank

    put '/api/v1/profile/avatar', params: { avatar: avatar_file }, headers: headers
    expect(response).to have_http_status(:ok)
    avatar_url = response.parsed_body.dig('data', 'avatar_url')

    expect(validated_user(headers)['avatar_url']).to eq(avatar_url)
  end

  it 'returns the new name and avatar after a combined update' do
    headers = api_token_headers
    cached = validated_user(headers)
    expect(cached['name']).to eq('Original Name')
    expect(cached['avatar_url']).to be_blank

    put '/api/v1/profile', params: { profile: { name: 'Updated Both', avatar: avatar_file } }, headers: headers
    expect(response).to have_http_status(:ok)

    fresh = validated_user(headers)
    expect(fresh['name']).to eq('Updated Both')
    expect(fresh['avatar_url']).to be_present
  end

  it 'returns the saved avatar even when the rest of the update is rejected' do
    headers = api_token_headers
    expect(validated_user(headers)['avatar_url']).to be_blank

    put '/api/v1/profile', params: { profile: { email: 'not-an-email', avatar: avatar_file } }, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)

    expect(validated_user(headers)['avatar_url']).to be_present
  end
end
