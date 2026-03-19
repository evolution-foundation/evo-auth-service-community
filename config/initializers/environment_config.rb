# Environment Configuration for EvoAuth Service
# Basic configurations needed for the app to work

Rails.application.configure do
  # Basic app configuration
  Rails.application.config.app_name = 'Evo Auth Service'
  Rails.application.config.app_url = 'http://localhost:3001'
  Rails.application.config.enable_account_signup = true

  # MFA configuration with defaults
  Rails.application.config.mfa_config = {
    issuer_name: 'Evo Auth Service',
    backup_codes_count: 10,
    email_otp_expires_in: 300,
    totp_drift_behind: 30,
    totp_drift_ahead: 30
  }

  Rails.logger.info "🔧 EvoAuth: Basic environment configuration loaded"
end
