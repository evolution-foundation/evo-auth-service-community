# frozen_string_literal: true

# Licensing runtime initialization.
# Runs after all Rails initializers have loaded.
# Skipped in test environment — specs control Licensing::Runtime.context directly.
Rails.application.config.after_initialize do
  next if Rails.env.test?

  ctx = Licensing::Activation.initialize_runtime

  # Rake tasks and consoles are short-lived: rotating the generation there
  # would kill the live chain and defer the next ping by a whole interval.
  long_lived = !defined?(Rails::Console) && File.basename($PROGRAM_NAME) != 'rake'
  Licensing::Heartbeat.schedule! if ctx.active? && long_lived
end
