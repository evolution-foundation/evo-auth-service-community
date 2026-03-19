# frozen_string_literal: true

module Licensing
  module Setup
    def self.perform(email:, name:, instance_id:, client_ip: nil, version: Activation::VERSION)
      geo    = Registration.geo_lookup(client_ip)
      result = Registration.direct_register(
        tier:        Activation::TIER,
        email:       email,
        name:        name,
        instance_id: instance_id,
        version:     version,
        country:     geo['country'],
        city:        geo['city']
      )

      Store.new.save_runtime_data(
        api_key:     result['api_key'],
        tier:        result['tier'],
        customer_id: result['customer_id']
      )

      Runtime.context.activate!(
        api_key:     result['api_key'],
        instance_id: instance_id
      )

      HeartbeatJob.set(wait: Heartbeat::INTERVAL).perform_later

      Rails.logger.info "[Setup] Installation completed (customer_id: #{result['customer_id']})"
      true

    rescue Transport::NetworkError, Transport::ResponseError => e
      Rails.logger.error "[Setup] Registration failed: #{e.message}"
      false
    rescue StandardError => e
      Rails.logger.error "[Setup] Unexpected error during installation: #{e.message}"
      false
    end
  end
end
