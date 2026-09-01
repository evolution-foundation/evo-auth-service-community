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

      Heartbeat.schedule!
      RetryPolicy.record_success!

      Rails.logger.info "[Setup] Installation completed (customer_id: #{result['customer_id']})"
      true

    rescue Transport::ResponseError => e
      RetryPolicy.record_failure!(retry_after: e.retry_after)
      # 429 is about timing so it stays retryable; any other 4xx answers the
      # same forever and :rejected (truthy) stops the SetupJob chain.
      if e.status_code&.between?(400, 499) && e.status_code != 429
        Rails.logger.error "[Setup] Registration rejected (HTTP #{e.status_code}) — not retrying"
        return :rejected
      end

      Rails.logger.error "[Setup] Registration failed: #{e.message}"
      false
    rescue Transport::NetworkError => e
      RetryPolicy.record_failure!
      Rails.logger.error "[Setup] Registration failed: #{e.message}"
      false
    rescue StandardError => e
      Rails.logger.error "[Setup] Unexpected error during installation: #{e.message}"
      false
    end
  end
end
