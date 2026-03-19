# frozen_string_literal: true

module Licensing
  module Activation
    TIER    = 'evo-ai-crm-community'.freeze
    VERSION = begin
      ENV['APP_VERSION'].presence ||
        File.read(Rails.root.join('VERSION')).strip.presence ||
        '1.0.0'
    rescue Errno::ENOENT
      ENV.fetch('APP_VERSION', '1.0.0')
    end.freeze

    def self.initialize_runtime(store: nil, version: VERSION)
      store ||= Store.new

      ctx = RuntimeContext.new(tier: TIER, version: version)

      instance_id = store.load_or_create_instance_id
      Rails.logger.info "[L] #001"

      runtime_data = store.load_runtime_data

      if runtime_data
        api_key = runtime_data['k']
        Rails.logger.info "[L] #002"

        begin
          transport = Transport.new(base_url: Endpoint.resolve_url, api_key: api_key)
          result    = transport.post_signed('/v1/activate', {
            instance_id: instance_id,
            version:     version
          })

          if result['status'] == 'active'
            ctx.activate!(api_key: api_key, instance_id: instance_id)
            Rails.logger.info "[L] #003"
          else
            _2s(ctx, "Activation returned status: #{result['status']}")
          end

        rescue Transport::NetworkError, Transport::ResponseError => e
          _2s(ctx, e.message)
        end

      else
        Rails.logger.warn "[L] #004"
        Rails.logger.warn "[L] #005"
        Rails.logger.warn "[L] #006"
      end

      Runtime.context = ctx
      ctx
    end

    def self.try_reactivate(store: nil, version: VERSION)
      store       ||= Store.new
      runtime_data  = store.load_runtime_data
      return false unless runtime_data

      instance_id = store.load_or_create_instance_id
      api_key     = runtime_data['k']

      transport = Transport.new(base_url: Endpoint.resolve_url, api_key: api_key)
      result    = transport.post_signed('/v1/activate', {
        instance_id: instance_id,
        version:     version
      })

      if result['status'] == 'active'
        Runtime.context.activate!(api_key: api_key, instance_id: instance_id)
        Rails.logger.info "[L] #reactivated"
        true
      else
        false
      end
    rescue StandardError
      false
    end

    def self._9ps(message)
      Rails.logger.fatal "[L] #007"
      abort("[Licensing] #{message}")
    end

    private_class_method def self._2s(_ctx, message)
      Rails.logger.warn "[L] #008"
      Rails.logger.warn "[L] #009"
    end
  end
end
