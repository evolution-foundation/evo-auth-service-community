# Logs the effective email-confirmation posture at boot so operators can see
# which posture the box derived (Story 8.3b / EVO-2016). The posture itself is
# computed per-request by EmailConfirmationPosture — this is observability only.
Rails.application.config.after_initialize do
  posture = EmailConfirmationPosture.required? ? 'required' : 'open'
  Rails.logger.info("[auth] email-confirmation posture: #{posture} — source: #{EmailConfirmationPosture.source}")
end
