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
        # No license on disk yet — try silent auto-activation via email before
        # falling back to the manual setup flow (which requires browser interaction).
        unless try_auto_register_from_env(ctx: ctx, store: store, instance_id: instance_id, version: version)
          Rails.logger.warn "[L] #004"
          Rails.logger.warn "[L] #005"
          Rails.logger.warn "[L] #006"
        end
      end

      Runtime.context = ctx
      ctx
    end

    # try_auto_register_from_env attempts a headless activation using only the
    # operator email from EVOLUTION_OPERATOR_EMAIL. The customer must have completed
    # at least one manual registration in the past.
    #
    # Returns true when the license was successfully activated. Returns false on
    # any failure — caller falls back to the manual setup flow.
    def self.try_auto_register_from_env(ctx:, store:, instance_id:, version:)
      email = ENV['EVOLUTION_OPERATOR_EMAIL'].to_s.strip
      return false if email.empty?

      result = Registration.auto_register(
        email:       email,
        tier:        TIER,
        instance_id: instance_id,
        version:     version
      )

      api_key = result['api_key']
      return false if api_key.to_s.empty?

      store.save_runtime_data(
        api_key:     api_key,
        tier:        result['tier'] || TIER,
        customer_id: result['customer_id']
      )

      ctx.activate!(api_key: api_key, instance_id: instance_id)
      Rails.logger.info "[Licensing] License activated automatically via EVOLUTION_OPERATOR_EMAIL"
      true

    rescue Transport::ResponseError => e
      # 404 (CUSTOMER_NOT_FOUND) is the expected first-time path — log calmly.
      if e.status_code == 404
        Rails.logger.info "[Licensing] Auto-activation skipped — email not registered yet. Falling back to manual setup."
      else
        Rails.logger.warn "[Licensing] Auto-activation rejected: #{e.message}. Falling back to manual setup."
      end
      false
    rescue Transport::NetworkError => e
      Rails.logger.warn "[Licensing] Auto-activation skipped — #{e.message}"
      false
    rescue StandardError => e
      Rails.logger.warn "[Licensing] Auto-activation failed with unexpected error: #{e.class}: #{e.message}"
      false
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
