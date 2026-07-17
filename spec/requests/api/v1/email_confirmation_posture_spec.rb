# frozen_string_literal: true

require 'rails_helper'

# Guard spec for Story 8.3b (EVO-2016): the email-confirmation posture derives
# from SMTP_ADDRESS presence; REQUIRE_EMAIL_CONFIRMATION only acts as an
# explicit override. The login barrier keys on confirmation_sent_at ("did this
# account ever get a confirmation email?"), so accounts born under an open
# posture — and pre-existing unconfirmed accounts amnestied by migration
# 20260706191528 — are grandfathered: no retroactive lockout when the posture
# flips to required.
RSpec.describe 'email-confirmation posture (EVO-2016)', type: :request do
  POSTURE_ENVS = %w[SMTP_ADDRESS REQUIRE_EMAIL_CONFIRMATION].freeze

  around do |example|
    original = POSTURE_ENVS.index_with { |k| ENV[k] }
    example.run
  ensure
    original.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  def set_posture_env(smtp: nil, explicit: nil)
    smtp.nil? ? ENV.delete('SMTP_ADDRESS') : ENV['SMTP_ADDRESS'] = smtp
    explicit.nil? ? ENV.delete('REQUIRE_EMAIL_CONFIRMATION') : ENV['REQUIRE_EMAIL_CONFIRMATION'] = explicit
  end

  let(:password) { 'Test123!@' }

  # Devise stamps confirmation_sent_at on every unconfirmed create even when no
  # email goes out; normalize to the scenario under test (grandfathered = nil,
  # the state the signup flow and the amnesty migration guarantee).
  def create_user(confirmed:, confirmation_sent: false)
    user = User.new(
      name: 'Posture Spec User',
      email: "posture-spec-#{SecureRandom.hex(4)}@example.com",
      password: password,
      password_confirmation: password
    )
    user.skip_confirmation_notification!
    user.confirmed_at = Time.current if confirmed
    user.save!
    user.update_column(:confirmation_sent_at, nil) unless confirmation_sent
    user.reload
  end

  def login(user)
    post '/api/v1/auth/login', params: { email: user.email, password: password }
  end

  before do
    allow(Licensing::Runtime).to receive(:context).and_return(
      instance_double(Licensing::RuntimeContext, active?: true, track_message: nil)
    )
    allow(RuntimeConfig).to receive(:account).and_return(nil)
  end

  describe '.log_boot_posture! (EVO-2146 — lockout detectable at boot)' do
    it 'warns LOUDLY when the barrier is forced without SMTP (lockout config)' do
      set_posture_env(smtp: nil, explicit: 'true')
      allow(EmailConfirmationPosture).to receive(:smtp_configured?).and_return(false)

      expect(Rails.logger).to receive(:info).with(/posture: required/)
      expect(Rails.logger).to receive(:warn).with(/LOCKOUT/)
      EmailConfirmationPosture.log_boot_posture!
    end

    it 'does not warn when an ALTERNATIVE mailer delivers (MAILER_TYPE=resend/bms)' do
      set_posture_env(smtp: nil, explicit: 'true')
      allow(EmailConfirmationPosture).to receive(:smtp_configured?).and_return(false)
      allow(EmailConfirmationPosture).to receive(:alternative_mailer_configured?).and_return(true)

      expect(Rails.logger).to receive(:info).with(/posture: required/)
      expect(Rails.logger).not_to receive(:warn)
      EmailConfirmationPosture.log_boot_posture!
    end

    it 'does not warn when the barrier is required WITH SMTP (deliverable)' do
      set_posture_env(smtp: 'smtp.example.com', explicit: nil)
      allow(EmailConfirmationPosture).to receive(:smtp_configured?).and_return(true)

      expect(Rails.logger).to receive(:info).with(/posture: required/)
      expect(Rails.logger).not_to receive(:warn)
      EmailConfirmationPosture.log_boot_posture!
    end

    it 'does not warn under the open posture (no SMTP, no override)' do
      set_posture_env(smtp: nil, explicit: nil)
      allow(EmailConfirmationPosture).to receive(:smtp_configured?).and_return(false)

      expect(Rails.logger).to receive(:info).with(/posture: open/)
      expect(Rails.logger).not_to receive(:warn)
      EmailConfirmationPosture.log_boot_posture!
    end
  end

  describe 'derivation from SMTP_ADDRESS' do
    it 'requires confirmation when SMTP_ADDRESS is set (unconfirmed user who got the email is barred)' do
      set_posture_env(smtp: 'smtp.example.com')
      user = create_user(confirmed: false, confirmation_sent: true)

      login(user)

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig('error', 'code')).to eq('EMAIL_NOT_CONFIRMED')
    end

    it 'stays open when SMTP_ADDRESS is absent (unconfirmed user logs in)' do
      set_posture_env(smtp: nil)
      user = create_user(confirmed: false, confirmation_sent: true)

      login(user)

      expect(response).to have_http_status(:ok)
    end

    # The posture must follow the same SMTP_ADDRESS lookup the mailer uses
    # (GlobalConfigService: installation_configs -> runtime_configs -> ENV), not
    # just the bare env. SMTP configured via the admin UI (installation_configs)
    # sends mail while SMTP_ADDRESS env is empty; keying off the env alone would
    # leave the barrier open while mail works (AC1 breach).
    it 'requires confirmation when SMTP is admin-configured (GlobalConfigService) with the env unset' do
      set_posture_env(smtp: nil)
      allow(GlobalConfigService).to receive(:load).and_call_original
      allow(GlobalConfigService).to receive(:load).with('SMTP_ADDRESS').and_return('smtp.example.com')
      user = create_user(confirmed: false, confirmation_sent: true)

      login(user)

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig('error', 'code')).to eq('EMAIL_NOT_CONFIRMED')
    end
  end

  describe 'explicit REQUIRE_EMAIL_CONFIRMATION override' do
    it 'false overrides an SMTP-derived required posture' do
      set_posture_env(smtp: 'smtp.example.com', explicit: 'false')
      user = create_user(confirmed: false, confirmation_sent: true)

      login(user)

      expect(response).to have_http_status(:ok)
    end

    it 'true overrides an SMTP-less open posture' do
      set_posture_env(smtp: nil, explicit: 'true')
      user = create_user(confirmed: false, confirmation_sent: true)

      login(user)

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig('error', 'code')).to eq('EMAIL_NOT_CONFIRMED')
    end
  end

  describe 'grandfathering (no retroactive lockout)' do
    it 'lets an unconfirmed account with no confirmation email on record log in under a required posture' do
      set_posture_env(smtp: 'smtp.example.com')
      user = create_user(confirmed: false, confirmation_sent: false)

      login(user)

      expect(response).to have_http_status(:ok)
    end

    it 'keeps confirmed accounts logging in under a required posture' do
      set_posture_env(smtp: 'smtp.example.com')
      user = create_user(confirmed: true)

      login(user)

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'signup posture' do
    def register(email)
      post '/api/v1/auth/register', params: {
        name: 'Posture Signup User',
        email: email,
        password: password,
        password_confirmation: password
      }
    end

    it 'under an open posture creates the account grandfathered (no confirmation email, sent_at nil)' do
      set_posture_env(smtp: nil)
      email = "posture-signup-#{SecureRandom.hex(4)}@example.com"

      expect { register(email) }.not_to have_enqueued_mail

      expect(response).to have_http_status(:created)
      expect(User.from_email(email).confirmation_sent_at).to be_nil
    end

    it 'under a required posture sends the confirmation email and bars login until confirmed' do
      set_posture_env(smtp: 'smtp.example.com')
      email = "posture-signup-#{SecureRandom.hex(4)}@example.com"

      register(email)

      expect(response).to have_http_status(:created)
      user = User.from_email(email)
      expect(user.confirmation_sent_at).to be_present

      post '/api/v1/auth/login', params: { email: email, password: password }
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig('error', 'code')).to eq('EMAIL_NOT_CONFIRMED')
    end
  end
end
