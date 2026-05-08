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

  let(:active_licensing_ctx) do
    instance_double(Licensing::RuntimeContext, active?: true, track_message: nil)
  end

  before do
    allow(Licensing::Runtime).to receive(:context).and_return(active_licensing_ctx)
    allow_any_instance_of(Api::BaseController).to receive(:authenticate_request!)
    allow_any_instance_of(Api::BaseController).to receive(:current_user).and_return(user)
    allow_any_instance_of(Api::BaseController).to receive(:set_current_user)
  end

  describe 'POST /api/v1/mfa/regenerate_backup_codes' do
    it 'returns 200' do
      post '/api/v1/mfa/regenerate_backup_codes'
      expect(response).to have_http_status(:ok)
    end

    it 'returns 10 plaintext backup codes' do
      post '/api/v1/mfa/regenerate_backup_codes'
      body = JSON.parse(response.body)
      expect(body.dig('data', 'backup_codes').length).to eq(10)
    end

    it 'returns 8-character alphanumeric codes' do
      post '/api/v1/mfa/regenerate_backup_codes'
      codes = JSON.parse(response.body).dig('data', 'backup_codes')
      expect(codes).to all(match(/\A[A-Z0-9]{8}\z/))
    end

    it 'stores codes hashed in the DB' do
      post '/api/v1/mfa/regenerate_backup_codes'
      user.reload
      expect(user.otp_backup_codes).to all(start_with('$2a$'))
    end

    it 'invalidates previous codes when called twice' do
      post '/api/v1/mfa/regenerate_backup_codes'
      first_codes = JSON.parse(response.body).dig('data', 'backup_codes')

      post '/api/v1/mfa/regenerate_backup_codes'
      user.reload

      first_codes.each do |code|
        expect(user.check_backup_code(code)).to be(false)
      end
    end
  end

  describe 'GET /api/v1/mfa/backup_codes' do
    it 'returns 200' do
      get '/api/v1/mfa/backup_codes'
      expect(response).to have_http_status(:ok)
    end

    it 'does not expose stored hashes to the client' do
      user.generate_otp_backup_codes!
      get '/api/v1/mfa/backup_codes'
      codes = JSON.parse(response.body).dig('data', 'backup_codes')
      expect(codes).to be_empty
    end
  end
end
