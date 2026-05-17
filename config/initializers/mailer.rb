# Require email providers and services
require_relative '../../lib/mail/bms_provider'
require_relative '../../lib/mail/resend_provider'
require_relative '../../lib/global_config_service'

Rails.application.configure do
  #########################################
  # Configuration Related to Action Mailer
  #########################################

  # We need the application frontend url to be used in our emails
  config.action_mailer.default_url_options = { host: ENV['FRONTEND_URL'] } if ENV['FRONTEND_URL'].present?

  # Set default sender email
  config.action_mailer.default_options = {
    from: ENV.fetch('MAILER_SENDER_EMAIL', 'noreply@evo-auth-service.com')
  }

  # We load certain mailer templates from our database. This ensures changes to it is reflected immediately
  config.action_mailer.perform_caching = false
  config.action_mailer.perform_deliveries = true
  config.action_mailer.raise_delivery_errors = true

  # SMTP settings are now loaded dynamically from GlobalConfigService at
  # delivery time (see ApplicationMailer).  The initializer still sets safe
  # defaults so Action Mailer has *something* configured at boot.
  smtp_settings = {
    address: ENV.fetch('SMTP_ADDRESS', 'localhost'),
    port: ENV.fetch('SMTP_PORT', 587)
  }

  smtp_settings[:authentication] = ENV.fetch('SMTP_AUTHENTICATION', 'login').to_sym if ENV['SMTP_AUTHENTICATION'].present?
  smtp_settings[:domain] = ENV['SMTP_DOMAIN'] if ENV['SMTP_DOMAIN'].present?
  smtp_settings[:user_name] = ENV.fetch('SMTP_USERNAME', nil)
  smtp_settings[:password] = ENV.fetch('SMTP_PASSWORD', nil)
  smtp_settings[:enable_starttls_auto] = ActiveModel::Type::Boolean.new.cast(ENV.fetch('SMTP_ENABLE_STARTTLS_AUTO', true))
  smtp_settings[:openssl_verify_mode] = ENV['SMTP_OPENSSL_VERIFY_MODE'] if ENV['SMTP_OPENSSL_VERIFY_MODE'].present?
  smtp_settings[:ssl] = ActiveModel::Type::Boolean.new.cast(ENV.fetch('SMTP_SSL', false)) if ENV['SMTP_SSL']
  smtp_settings[:tls] = ActiveModel::Type::Boolean.new.cast(ENV.fetch('SMTP_TLS', false)) if ENV['SMTP_TLS']
  smtp_settings[:open_timeout] = ENV['SMTP_OPEN_TIMEOUT'].to_i if ENV['SMTP_OPEN_TIMEOUT'].present?
  smtp_settings[:read_timeout] = ENV['SMTP_READ_TIMEOUT'].to_i if ENV['SMTP_READ_TIMEOUT'].present?

  config.action_mailer.smtp_settings = smtp_settings

  # Register email providers
  ActionMailer::Base.add_delivery_method :bms, Mail::BmsProvider
  ActionMailer::Base.add_delivery_method :resend, Mail::ResendProvider

  # You can use letter opener for your local development
  config.action_mailer.delivery_method = :letter_opener if Rails.env.development? && ENV['LETTER_OPENER']
end

Rails.application.config.after_initialize do
  unless Rails.env.test?
    begin
      mailer_type = GlobalConfigService.load('MAILER_TYPE', 'smtp')

      case mailer_type
      when 'bms'
        bms_api_key = GlobalConfigService.load('BMS_API_SECRET', nil)
        if bms_api_key.present?
          ActionMailer::Base.delivery_method = :bms
          Rails.logger.info "📧 EvoAuth MAILER: BMS configured as delivery method"
        else
          Rails.logger.warn "📧 EvoAuth MAILER: MAILER_TYPE=bms but BMS_API_SECRET not set, falling back to SMTP"
        end
      when 'resend'
        resend_api_key = GlobalConfigService.load('RESEND_API_SECRET', ENV.fetch('RESEND_API_KEY', nil))
        if resend_api_key.present?
          ActionMailer::Base.delivery_method = :resend
          Rails.logger.info "📧 EvoAuth MAILER: Resend configured as delivery method"
        else
          Rails.logger.warn "📧 EvoAuth MAILER: MAILER_TYPE=resend but RESEND_API_SECRET not set, falling back to SMTP"
        end
      else
        Rails.logger.info "📧 EvoAuth MAILER: Using SMTP delivery method"
      end
    rescue => e
      Rails.logger.warn "📧 EvoAuth MAILER: Error loading provider config: #{e.message}, using SMTP"
    end
  end
end
