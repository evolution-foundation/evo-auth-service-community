class ApplicationMailer < ActionMailer::Base
  layout "mailer"

  default from: ->(*) { ApplicationMailer.get_mailer_sender_email }

  before_action :load_dynamic_mail_settings
  after_action :apply_dynamic_delivery_settings

  def self.get_mailer_sender_email
    GlobalConfigService.load('MAILER_SENDER_EMAIL', 'noreply@evo-auth-service.com')
  end

  private

  def load_dynamic_mail_settings
    mailer_type = GlobalConfigService.load('MAILER_TYPE', 'smtp')

    case mailer_type
    when 'bms'
      if GlobalConfigService.load('BMS_API_SECRET', nil).present?
        @dynamic_delivery_method = :bms
        @dynamic_delivery_options = {}
      end
    when 'resend'
      resend_api_key = GlobalConfigService.load('RESEND_API_SECRET', ENV.fetch('RESEND_API_KEY', nil))
      if resend_api_key.present?
        @dynamic_resend_api_key = resend_api_key
        @dynamic_delivery_method = :resend
        @dynamic_delivery_options = {}
      end
    else
      load_dynamic_smtp_settings
    end
  rescue => e
    Rails.logger.warn "Failed to load dynamic mail settings: #{e.message}"
  end

  def load_dynamic_smtp_settings
    address = GlobalConfigService.load('SMTP_ADDRESS', ENV.fetch('SMTP_ADDRESS', nil))
    unless address.present?
      Rails.logger.warn "EvoAuth MAILER: SMTP_ADDRESS not configured — skipping dynamic SMTP setup"
      return
    end

    smtp = (self.class.smtp_settings || {}).dup
    smtp[:address] = address
    smtp[:port] = GlobalConfigService.load('SMTP_PORT', ENV.fetch('SMTP_PORT', 587)).to_i
    smtp[:user_name] = GlobalConfigService.load('SMTP_USERNAME', ENV.fetch('SMTP_USERNAME', nil))
    smtp[:password] = GlobalConfigService.load('SMTP_PASSWORD_SECRET', ENV.fetch('SMTP_PASSWORD', nil))
    smtp[:enable_starttls_auto] = ActiveModel::Type::Boolean.new.cast(
      GlobalConfigService.load('SMTP_ENABLE_STARTTLS_AUTO', ENV.fetch('SMTP_ENABLE_STARTTLS_AUTO', true))
    )

    auth = GlobalConfigService.load('SMTP_AUTHENTICATION', ENV.fetch('SMTP_AUTHENTICATION', nil))
    smtp[:authentication] = auth.to_sym if auth.present?

    domain = GlobalConfigService.load('SMTP_DOMAIN', ENV.fetch('SMTP_DOMAIN', nil))
    smtp[:domain] = domain if domain.present?

    verify_mode = GlobalConfigService.load('SMTP_OPENSSL_VERIFY_MODE', ENV.fetch('SMTP_OPENSSL_VERIFY_MODE', nil))
    smtp[:openssl_verify_mode] = verify_mode if verify_mode.present?

    @dynamic_delivery_method = :smtp
    @dynamic_delivery_options = smtp
  end

  def apply_dynamic_delivery_settings
    return unless @dynamic_delivery_method

    options = @dynamic_delivery_options || {}
    options = options.merge(api_key: @dynamic_resend_api_key) if @dynamic_delivery_method == :resend && @dynamic_resend_api_key

    delivery_class = self.class.delivery_methods[@dynamic_delivery_method]
    if delivery_class.nil?
      Rails.logger.warn "ApplicationMailer: unregistered delivery method '#{@dynamic_delivery_method}' — passing symbol directly, mail gem may reject it"
      delivery_class = @dynamic_delivery_method
    end
    message.delivery_method(delivery_class, options)
  end
end
