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

  describe 'with an already revoked token' do
    it 'returns 200 and still clears the cookies' do
      token = login.dig('token', 'access_token')
      Doorkeeper::AccessToken.where(resource_owner_id: user.id).update_all(revoked_at: Time.current)
      cookies[:_evo_at] = token

      logout_with_token(token)

      expect(response).to have_http_status(:ok)
      cookie_str = Array(response.headers['Set-Cookie']).join("\n")
      expect(cookie_str).to match(/_evo_at=;/)
      expect(cookie_str).to match(/_evo_rt=;/)
    end
  end

  describe 'without any token' do
    it 'returns 200 on repeated calls' do
      logout_without_token
      expect(response).to have_http_status(:ok)

      logout_without_token
      expect(response).to have_http_status(:ok)
    end
  end
end
