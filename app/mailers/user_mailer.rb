# frozen_string_literal: true

class UserMailer < ApplicationMailer
  def two_factor_authentication_code(user, code)
    @user = user
    @code = code

    sender = GlobalConfigService.load('MAILER_SENDER_EMAIL', 'noreply@evo-auth-service.com')

    mail(
      to: user.email,
      from: sender,
      subject: "Your verification code: #{code}"
    )
  end
end
