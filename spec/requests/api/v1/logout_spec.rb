# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'POST /api/v1/auth/logout', type: :request do
  let(:password) { 'Test123!@' }

  let(:user) do
    User.create!(
      name: 'Logout User',
      email: "logout-#{SecureRandom.hex(4)}@example.com",
      password: password,
      password_confirmation: password,
      confirmed_at: Time.current
    )
  end

  before { Rails.cache.clear }

  def login_token
    post '/api/v1/auth/login', params: { email: user.email, password: password }, as: :json
    expect(response).to have_http_status(:ok)
    access_token = response.parsed_body.dig('data', 'token', 'access_token')
    Doorkeeper::AccessToken.find_by!(token: access_token)
  end

  def logout(headers: {}, as_json: true)
    if as_json
      post '/api/v1/auth/logout', headers: headers, as: :json
    else
      post '/api/v1/auth/logout', headers: headers, params: 'x=1', env: { 'CONTENT_TYPE' => 'application/x-www-form-urlencoded' }
    end
  end

  def expired_cookie?(name)
    line = Array(response.headers['Set-Cookie']).flat_map { |h| h.split("\n") }.find { |l| l.start_with?("#{name}=") }
    line.present? && line.match?(/max-age=0|expires=Thu, 01 Jan 1970/i)
  end

  it 'revokes every session token of the user and expires both cookies' do
    token = login_token
    other_session = login_token
    token.update_columns(revoked_at: nil)

    logout(headers: { 'Authorization' => "Bearer #{token.token}" })

    expect(response).to have_http_status(:ok)
    expect(token.reload.revoked_at).to be_present
    expect(other_session.reload.revoked_at).to be_present
    expect(expired_cookie?('_evo_at')).to be(true)
    expect(expired_cookie?('_evo_rt')).to be(true)
  end

  it 'expires both cookies when the token was already revoked' do
    token = login_token
    token.revoke
    cookies[:_evo_at] = token.token

    logout(headers: { 'Authorization' => "Bearer #{token.token}" })

    expect(response).to have_http_status(:ok)
    expect(expired_cookie?('_evo_at')).to be(true)
    expect(expired_cookie?('_evo_rt')).to be(true)
  end

  it 'revokes the session found through the cookies when no token header is sent' do
    token = login_token
    cookies[:_evo_rt] = token.refresh_token

    logout

    expect(response).to have_http_status(:ok)
    expect(token.reload.revoked_at).to be_present
  end

  it 'revokes an access token kept only in the _evo_at cookie' do
    token = login_token
    cookies.delete('_evo_rt')
    cookies[:_evo_at] = token.token

    logout

    expect(response).to have_http_status(:ok)
    expect(token.reload.revoked_at).to be_present
  end

  it 'refuses a form post without a token header and keeps the session' do
    token = login_token
    cookies[:_evo_rt] = token.refresh_token

    logout(as_json: false)

    expect(response).to have_http_status(:unauthorized)
    expect(token.reload.revoked_at).to be_nil
  end
end
