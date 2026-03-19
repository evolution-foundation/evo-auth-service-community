class ApplicationMailer < ActionMailer::Base
  layout "mailer"

  default from: ->(*) { GlobalConfigService.load('MAILER_SENDER_EMAIL', 'noreply@evo-auth-service.com') }

  def self.get_mailer_sender_email
    GlobalConfigService.load('MAILER_SENDER_EMAIL', 'noreply@evo-auth-service.com')
  end
end
