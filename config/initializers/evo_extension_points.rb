# frozen_string_literal: true

# Touch each EvoExtensionPoints sub-module at boot so that any autoload
# / Zeitwerk issue surfaces immediately rather than at the first request.
# Community ships with no overrides registered; consumers wire their own
# replacements from a Railtie initializer that runs before this one
# (Rails runs initializers in declared order; the after_initialize hook
# below runs after both, so consumer overrides are already installed).
Rails.application.config.after_initialize do
  loaded_keys = EvoExtensionPoints::KNOWN_KEYS
  versions = {
    auth_bridge: EvoExtensionPoints::AuthBridge::VERSION,
    token_claims: EvoExtensionPoints::TokenClaims::VERSION,
    login_gate: EvoExtensionPoints::LoginGate::VERSION
  }

  Rails.logger.info(
    "[EvoExtensionPoints] loaded keys=#{loaded_keys.inspect} versions=#{versions.inspect}"
  )
end
