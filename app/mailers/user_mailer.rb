# frozen_string_literal: true

class UserMailer < ApplicationMailer
  def two_factor_authentication_code(user, code)
    @user = user
    @code = code

    mail(
      to: user.email,
      subject: "Your verification code: #{code}"
    )
  end
end
