# Email-confirmation posture, derived from SMTP presence (Story 8.3b / EVO-2016).
#
# Default: SMTP_ADDRESS present => new signups must confirm before logging in;
# absent => no barrier (the confirmation email could never be delivered anyway,
# so requiring it would lock every new account out).
#
# REQUIRE_EMAIL_CONFIRMATION, when EXPLICITLY set, overrides the derivation in
# both directions — the cloud pins the posture regardless of its SMTP wiring.
# An unset or empty env falls through to the derived default.
module EmailConfirmationPosture
  module_function

  def required?
    explicit = ENV['REQUIRE_EMAIL_CONFIRMATION']
    return ActiveModel::Type::Boolean.new.cast(explicit) if explicit.present?

    ENV['SMTP_ADDRESS'].present?
  end

  def source
    ENV['REQUIRE_EMAIL_CONFIRMATION'].present? ? 'REQUIRE_EMAIL_CONFIRMATION (explicit override)' : 'SMTP_ADDRESS presence (derived)'
  end
end
