# frozen_string_literal: true

require 'rails_helper'

# Regression spec for EVO-1104.
# Confirms that users whose backup codes were invalidated by the plaintext
# migration (InvalidatePlaintextBackupCodes) can still log in without being
# stuck in an MFA challenge loop.
#
# After the migration these users have:
#   otp_required_for_login: true  (MFA was configured before EVO-991)
#   mfa_confirmed_at:        nil  (cleared by migration → mfa_enabled? returns false)
#   otp_backup_codes:        []   (cleared by migration)
#
# Because mfa_enabled? == false, auth_controller#login skips render_mfa_required
# and calls render_successful_login directly, returning mfa_setup_incomplete: true
# so the frontend can prompt the user to reconfigure MFA.
RSpec.describe 'POST /api/v1/auth/login — mfa_setup_incomplete bypass (EVO-1104)', type: :request do
  let(:password) { 'Test123!@' }

  let(:user) do
    User.create!(
      name: 'Legacy MFA User',
      email: "auth-spec-#{SecureRandom.hex(4)}@example.com",
      password: password,
      password_confirmation: password,
      confirmed_at: Time.current,
      otp_required_for_login: true,
      mfa_method: :totp
    )
  end

  before do
    # Simulate the state left by InvalidatePlaintextBackupCodes migration.
    User.where(id: user.id).update_all(otp_backup_codes: [], mfa_confirmed_at: nil)
    user.reload

    allow(Licensing::Runtime).to receive(:context).and_return(
      instance_double(Licensing::RuntimeContext, active?: true, track_message: nil)
    )
    allow(RuntimeConfig).to receive(:account).and_return(nil)

    store_double = instance_double(Licensing::Store,
      load_or_create_instance_id: nil,
      load_runtime_data: nil)
    allow(Licensing::Store).to receive(:new).and_return(store_double)
  end

  let(:login_headers) { { 'Host' => 'localhost' } }

  it 'returns 200 without triggering an MFA challenge' do
    post '/api/v1/auth/login', params: { email: user.email, password: password }, headers: login_headers

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body.dig('data', 'mfa_required')).to be_nil
  end

  it 'includes mfa_setup_incomplete: true in the user payload so the frontend can redirect to re-setup' do
    post '/api/v1/auth/login', params: { email: user.email, password: password }, headers: login_headers

    body = JSON.parse(response.body)
    expect(body.dig('data', 'user', 'mfa_setup_incomplete')).to be(true)
  end

  it 'issues a valid access token so the user can reach the MFA re-setup endpoints' do
    post '/api/v1/auth/login', params: { email: user.email, password: password }, headers: login_headers

    body = JSON.parse(response.body)
    expect(body.dig('data', 'token', 'access_token')).to be_present
  end
end
