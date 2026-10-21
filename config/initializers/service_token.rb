Rails.application.config.after_initialize do
  next if Rails.env.test?

  ServiceTokenAuthConcern.verify_configured!
end
