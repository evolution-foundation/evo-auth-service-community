# frozen_string_literal: true

# Licensing runtime initialization.
# Runs after all Rails initializers have loaded.
# Skipped in test environment — specs control Licensing::Runtime.context directly.
Rails.application.config.after_initialize do
  next if Rails.env.test?

  ctx = Licensing::Activation.initialize_runtime

  # Schedule first heartbeat after the initial interval if license is active.
  Licensing::HeartbeatJob.set(wait: Licensing::Heartbeat::INTERVAL).perform_later if ctx.active?
end
