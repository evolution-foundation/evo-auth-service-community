Rails.application.config.after_initialize do
  next if Rails.env.test?

  InstallationConfig.encryption_key
end
