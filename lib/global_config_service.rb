# frozen_string_literal: true

# Unified configuration reader with a three-tier fallback chain:
#
#   1. installation_configs  — admin-managed settings (SMTP, storage, OAuth …)
#   2. runtime_configs       — bootstrap / first-setup data (account JSON …)
#   3. ENV                   — environment variables
#
# The first non-nil hit wins. installation_configs results are cached for 60 s
# inside InstallationConfig.get_value so repeated calls are cheap.
class GlobalConfigService
  def self.load(config_key, default_value = nil)
    # Priority 1: installation_configs (admin-managed, 60 s cache)
    ic_value = InstallationConfig.get_value(config_key)
    return ic_value unless ic_value.nil?

    # Priority 2: runtime_configs (bootstrap data)
    rc_value = RuntimeConfig.get(config_key)
    return rc_value if rc_value.present?

    # Priority 3: ENV
    env_value = ENV.fetch(config_key, nil)
    return env_value if env_value.present?

    # Priority 4: caller-supplied default
    default_value
  rescue StandardError => e
    Rails.logger.warn("GlobalConfigService.load(#{config_key}) failed: #{e.message}")
    ENV.fetch(config_key, default_value)
  end
end
