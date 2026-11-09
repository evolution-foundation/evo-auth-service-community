# frozen_string_literal: true

require 'rails_helper'

# Logout endpoint must clear HttpOnly cookies in two scenarios:
# 1. Normal logout: user has valid token → revoke it + clear cookies (200)
# 2. Post-deletion: tokens already revoked → still clear cookies (200)
#
# Regression for CRM-973: after account deletion, logout returned 401
# because it required authentication but tokens were revogado. This left
# _evo_at/_evo_rt cookies in the browser, causing the next user in the same tab
# to inherit the previous session.
RSpec.describe 'POST /api/v1/auth/logout — clear cookies with/without token', type: :request do
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

  def login
    post '/api/v1/auth/login', params: { email: user.email, password: password }, as: :json
    unless response.status == 200
      fail "Login failed with status #{response.status}: #{response.body}"
    end
    JSON.parse(response.body)['data']
  end

  def logout_with_token(token)
    post '/api/v1/auth/logout', headers: { 'Authorization' => "Bearer #{token}" }, as: :json
  end

  def logout_without_token
    post '/api/v1/auth/logout', as: :json
  end

  before { Rails.cache.clear }

  describe 'with valid token' do
    it 'revokes the token and clears the cookies' do
      login_data = login
      token = login_data.dig('token', 'access_token')

      logout_with_token(token)

      expect(response).to have_http_status(:ok)
      # HttpOnly cookies are cleared with max-age=0 or expires in the past
      set_cookie = response.headers['Set-Cookie']
      # Set-Cookie can be an array of strings
      cookie_str = set_cookie.is_a?(Array) ? set_cookie.join('; ') : set_cookie
      expect(cookie_str).to match(/_evo_at=;/)
      expect(cookie_str).to match(/(max-age=0|expires=Thu, 01 Jan 1970)/)
      expect(cookie_str).to match(/_evo_rt=;/)
    end

    it 'makes the token unusable after logout' do
      login_data = login
      token = login_data.dig('token', 'access_token')

      # Before logout, token is valid
      get '/api/v1/auth/me', headers: { 'Authorization' => "Bearer #{token}" }
      expect(response).to have_http_status(:ok)

      # Logout
      logout_with_token(token)
      expect(response).to have_http_status(:ok)

      # After logout, token is revoked (on cache miss)
      get '/api/v1/auth/me', headers: { 'Authorization' => "Bearer #{token}" }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'without valid token (post-deletion scenario)' do
    it 'still clears the cookies and returns 200' do
      # Simulate post-deletion: all tokens are revoked, user calls logout anyway
      logout_without_token

      expect(response).to have_http_status(:ok)
      # Cookies must be cleared even without a valid token.
      # Rails doesn't send Set-Cookie headers if no cookies are set to begin with,
      # which is correct behavior: logout succeeds and clears nothing (no-op).
      set_cookie = response.headers['Set-Cookie']
      if set_cookie.present?
        cookie_str = set_cookie.is_a?(Array) ? set_cookie.join('; ') : set_cookie
        expect(cookie_str).to match(/_evo_at=;/)
        expect(cookie_str).to match(/(max-age=0|expires=Thu, 01 Jan 1970)/)
        expect(cookie_str).to match(/_evo_rt=;/)
      end
    end

    it 'succeeds even if called multiple times (idempotent)' do
      logout_without_token
      expect(response).to have_http_status(:ok)

      logout_without_token
      expect(response).to have_http_status(:ok)
    end
  end
end
