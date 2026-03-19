class GlobalConfig
  class << self
    def get(*args)
      config_keys = *args
      config = {}

      config_keys.each do |config_key|
        config[config_key] = load_from_db(config_key)
      end

      config.with_indifferent_access
    end

    def get_value(key)
      load_from_db(key)
    end

    private

    def load_from_db(config_key)
      value = db_lookup(config_key)
      return value unless value.nil?

      ENV.fetch(config_key, nil)
    end

    def db_lookup(config_key)
      result = ActiveRecord::Base.connection.exec_query(
        "SELECT value FROM runtime_configs WHERE key = $1 LIMIT 1",
        "GlobalConfig",
        [ActiveRecord::Relation::QueryAttribute.new("key", config_key, ActiveRecord::Type::String.new)]
      )

      return nil if result.rows.empty?

      result.rows.first.first
    rescue StandardError => e
      Rails.logger.warn "GlobalConfig: Error reading #{config_key} from DB: #{e.message}"
      nil
    end
  end
end
