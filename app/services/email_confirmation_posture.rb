# Email-confirmation posture, derived from SMTP presence (Story 8.3b / EVO-2016).
#
# Default: SMTP configured => new signups must confirm before logging in;
# absent => no barrier (the confirmation email could never be delivered anyway,
# so requiring it would lock every new account out).
#
# "SMTP configured" is resolved through the SAME chain the mailer uses to send
# (GlobalConfigService: installation_configs -> runtime_configs -> ENV), not
# just the raw SMTP_ADDRESS env var. If SMTP is set via the admin UI
# (installation_configs) the mailer sends but the env is empty; keying the
# posture off the bare env would leave the barrier open while mail works —
# reintroducing the loose enforcement this story removes (AC1).
#
# REQUIRE_EMAIL_CONFIRMATION, when EXPLICITLY set, overrides the derivation in
# both directions — the cloud pins the posture regardless of its SMTP wiring.
# An unset or empty env falls through to the derived default.
module EmailConfirmationPosture
  module_function

  def required?
    explicit = ENV['REQUIRE_EMAIL_CONFIRMATION']
    return ActiveModel::Type::Boolean.new.cast(explicit) if explicit.present?

    smtp_configured?
  end

  # Mirrors the mailer's SMTP_ADDRESS lookup (ApplicationMailer#load_dynamic_smtp_settings)
  # so the posture tracks actual deliverability. Falls back to the bare env if
  # the config store can't be read (e.g. boot before the DB is up); the login
  # barrier fails closed either way — it only bars when SMTP resolves present.
  def smtp_configured?
    GlobalConfigService.load('SMTP_ADDRESS').present?
  rescue StandardError
    ENV['SMTP_ADDRESS'].present?
  end

  def source
    ENV['REQUIRE_EMAIL_CONFIRMATION'].present? ? 'REQUIRE_EMAIL_CONFIRMATION (explicit override)' : 'SMTP_ADDRESS presence (derived)'
  end
end
