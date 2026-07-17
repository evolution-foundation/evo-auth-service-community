# Logs the effective email-confirmation posture at boot so operators can see
# which posture the box derived (Story 8.3b / EVO-2016). The posture itself is
# computed per-request by EmailConfirmationPosture — this is observability only.
# EVO-2146: it also shouts LOCKOUT when the barrier is forced without SMTP (logic
# and specs in EmailConfirmationPosture.log_boot_posture!).
Rails.application.config.after_initialize do
  EmailConfirmationPosture.log_boot_posture!
end
