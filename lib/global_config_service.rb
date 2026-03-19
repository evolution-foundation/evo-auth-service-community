class GlobalConfigService
  def self.load(config_key, default_value = nil)
    config = GlobalConfig.get(config_key)[config_key]
    return config unless config.nil?

    env_value = ENV.fetch(config_key, nil)
    return env_value if env_value.present?

    default_value
  end
end
