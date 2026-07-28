# frozen_string_literal: true

require 'rails_helper'

# Confirming the email must invalidate the token-validation cache: it holds the
# serialized user (with `confirmed`) for 5 minutes, so without invalidation
# someone who just confirmed keeps being seen as unverified for up to 5 minutes.
RSpec.describe 'confirmation invalidates the token-validation cache', type: :request do
  let(:password) { 'Test123!@' }

  def create_unconfirmed_user
    user = User.new(
      name: 'Confirm Cache Spec',
      email: "confirm-cache-#{SecureRandom.hex(4)}@example.com",
      password: password,
      password_confirmation: password
    )
    user.skip_confirmation_notification!
    user.save!
    user
  end

  # `generate_confirmation_token!` returns the save result, not the token.
  def confirmation_token_for(user)
    user.send(:generate_confirmation_token!)
    user.reload.confirmation_token
  end

  # `application_id` is NOT NULL here and the test DB seeds no application. The
  # model is `OauthApplication`, not `Doorkeeper::Application`.
  def bearer_token_for(user)
    app = OauthApplication.first || OauthApplication.create!(
      name: 'Spec App', redirect_uri: 'urn:ietf:wg:oauth:2.0:oob', scopes: 'public'
    )
    Doorkeeper::AccessToken.create!(
      application: app, resource_owner_id: user.id, scopes: 'public', expires_in: 2.hours
    )
  end

  it 'calls the invalidation helper for the confirmed user' do
    user = create_unconfirmed_user
    token = confirmation_token_for(user)

    expect(TokenValidationService)
      .to receive(:invalidate_cache_for_user)
      .with(having_attributes(id: user.id))

    get "/auth/confirmation?confirmation_token=#{token}"

    expect(user.reload.confirmed_at).to be_present
  end

  it 'does NOT invalidate when the token is invalid — nothing was confirmed' do
    expect(TokenValidationService).not_to receive(:invalidate_cache_for_user)

    get '/auth/confirmation?confirmation_token=nope-not-a-real-token'
  end

  it 'serves the fresh confirmed state on the next validation, not the cached one' do
    user = create_unconfirmed_user
    token = confirmation_token_for(user)

    # Prime the cache: validate once BEFORE confirming.
    access_token = bearer_token_for(user)
    post '/api/v1/auth/validate', headers: { 'Authorization' => "Bearer #{access_token.token}" }
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).dig('data', 'user', 'confirmed')).to be(false)

    get "/auth/confirmation?confirmation_token=#{token}"

    post '/api/v1/auth/validate', headers: { 'Authorization' => "Bearer #{access_token.token}" }
    expect(JSON.parse(response.body).dig('data', 'user', 'confirmed')).to be(true)
  end
end
