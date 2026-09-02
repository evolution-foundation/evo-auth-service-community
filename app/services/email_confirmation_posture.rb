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

  # Boot observability (called by the initializer; a method so it stays testable).
  # Beyond the effective posture, it DETECTS the lockout config (EVO-2146): a
  # barrier FORCED by an explicit override while SMTP is absent = every new signup
  # is locked out forever (the confirmation email will never be delivered). The
  # derivation never produces this state — only the explicit override can.
  def log_boot_posture!
    posture = required? ? 'required' : 'open'
    Rails.logger.info("[auth] email-confirmation posture: #{posture} — source: #{source}")

    return unless required? && !smtp_configured? && !alternative_mailer_configured?

    Rails.logger.warn(
      '[auth] LOCKOUT: REQUIRE_EMAIL_CONFIRMATION forces the confirmation barrier, '       'but no resolvable mailer is configured — new signups will NOT be able to log '       'in. Configure SMTP (env or admin panel) or remove the override (the derived '       'posture resolves on its own). If SMTP lives only in installation_configs and '       'the database was down at this boot, ignore this warning.'
    )
  end

  # The posture derives from SMTP alone (EVO-2016 contract), but the lockout warn
  # must not shout when an ALTERNATIVE mailer delivers (MAILER_TYPE resend/bms) —
  # it would be a permanent false alarm on a healthy install.
  def alternative_mailer_configured?
    mailer_type = GlobalConfigService.load('MAILER_TYPE', ENV.fetch('MAILER_TYPE', nil)).to_s.downcase
    %w[resend bms].include?(mailer_type)
  rescue StandardError
    %w[resend bms].include?(ENV['MAILER_TYPE'].to_s.downcase)
  end
end
