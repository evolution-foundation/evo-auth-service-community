# frozen_string_literal: true

require 'rails_helper'

# Regression spec for EVO-991.
# POST /api/v1/mfa/regenerate_backup_codes was returning 500 due to a call
# to the non-existent method #generate_backup_codes instead of
# #generate_otp_backup_codes!.
RSpec.describe 'MFA backup codes endpoints', type: :request do
  let(:user) do
    User.create!(
      name: 'MFA User',
      email: "mfa-spec-#{SecureRandom.hex(4)}@example.com",
      password: 'Test123!@',
      password_confirmation: 'Test123!@',
      confirmed_at: Time.current,
      otp_required_for_login: true,
      mfa_method: :totp
    )
  end

  let(:access_token) { AccessToken.create!(owner: user, name: 'mfa-spec-token', scopes: 'default') }
  let(:auth_headers) { { 'api_access_token' => access_token.token, 'Host' => 'localhost' } }

  before do
    allow(Licensing::Runtime).to receive(:context).and_return(
      instance_double(Licensing::RuntimeContext, active?: true, track_message: nil)
    )
  end

  describe 'POST /api/v1/mfa/regenerate_backup_codes' do
    it 'returns 200' do
      post '/api/v1/mfa/regenerate_backup_codes', headers: auth_headers
      expect(response).to have_http_status(:ok)
    end

    it 'returns 10 plaintext backup codes' do
      post '/api/v1/mfa/regenerate_backup_codes', headers: auth_headers
      body = JSON.parse(response.body)
      expect(body.dig('data', 'backup_codes').length).to eq(10)
    end

    it 'returns 8-character alphanumeric codes' do
      post '/api/v1/mfa/regenerate_backup_codes', headers: auth_headers
      codes = JSON.parse(response.body).dig('data', 'backup_codes')
      expect(codes).to all(match(/\A[A-Z0-9]{8}\z/))
    end

    it 'stores codes hashed in the DB' do
      post '/api/v1/mfa/regenerate_backup_codes', headers: auth_headers
      user.reload
      expect(user.otp_backup_codes).to all(match(/\A\$2[aby]\$/))
    end

    it 'invalidates previous codes when called twice' do
      post '/api/v1/mfa/regenerate_backup_codes', headers: auth_headers
      first_codes = JSON.parse(response.body).dig('data', 'backup_codes')

      post '/api/v1/mfa/regenerate_backup_codes', headers: auth_headers
      user.reload

      first_codes.each do |code|
        expect(user.check_backup_code(code)).to be(false)
      end
    end
  end

  describe 'GET /api/v1/mfa/backup_codes' do
    it 'returns 200' do
      get '/api/v1/mfa/backup_codes', headers: auth_headers
      expect(response).to have_http_status(:ok)
    end

    it 'returns remaining_codes_count without exposing hashes' do
      user.generate_otp_backup_codes!
      get '/api/v1/mfa/backup_codes', headers: auth_headers
      data = JSON.parse(response.body)['data']
      expect(data).to have_key('remaining_codes_count')
      expect(data['remaining_codes_count']).to eq(10)
      expect(data).not_to have_key('backup_codes')
    end

    it 'reports zero when no codes exist' do
      get '/api/v1/mfa/backup_codes', headers: auth_headers
      expect(JSON.parse(response.body).dig('data', 'remaining_codes_count')).to eq(0)
    end
  end

  describe 'POST /api/v1/mfa/verify_totp — backup code login flow (AC #4)' do
    before do
      User.where(id: user.id).update_all(otp_secret: ROTP::Base32.random)
      user.reload
    end

    let!(:plaintext_codes) { user.generate_otp_backup_codes! }
    let(:valid_code) { plaintext_codes.first }

    it 'accepts a valid backup code and returns 200' do
      post '/api/v1/mfa/verify_totp', params: { code: valid_code }, headers: auth_headers
      expect(response).to have_http_status(:ok)
    end

    it 'consumes the backup code on first use — remaining count decreases by one' do
      post '/api/v1/mfa/verify_totp', params: { code: valid_code }, headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(user.reload.otp_backup_codes.length).to eq(9)
    end

    it 'rejects the same backup code on second use' do
      post '/api/v1/mfa/verify_totp', params: { code: valid_code }, headers: auth_headers
      post '/api/v1/mfa/verify_totp', params: { code: valid_code }, headers: auth_headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'rejects an unknown code with 422' do
      post '/api/v1/mfa/verify_totp', params: { code: 'XXXXXXXX' }, headers: auth_headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'POST /api/v1/mfa/verify_totp?setup=true — token cache invalidation (EVO-1104)' do
    before do
      User.where(id: user.id).update_all(otp_secret: ROTP::Base32.random)
      user.reload
    end

    it 'invalidates the TokenValidationService cache after MFA setup completes' do
      totp_code = ROTP::TOTP.new(user.otp_secret).now

      expect(TokenValidationService).to receive(:invalidate_cache_for_user).with(user)

      post '/api/v1/mfa/verify_totp', params: { code: totp_code, setup: true }, headers: auth_headers
    end
  end
end
