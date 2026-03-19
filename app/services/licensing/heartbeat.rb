# frozen_string_literal: true

module Licensing
  module Heartbeat
    INTERVAL = 5.minutes

    def self.ping(ctx: Runtime.context, version: Activation::VERSION)
      return unless ctx&.active?

      messages_sent = ctx.collect_and_reset_messages

      transport = Transport.new(base_url: Endpoint.resolve_url, api_key: ctx.api_key)
      result    = transport.post_signed('/v1/heartbeat', {
        instance_id:   ctx.instance_id,
        version:       version,
        messages_sent: messages_sent
      })

      case result['status']
      when 'active'
        Rails.logger.debug "[L] #001"
      when 'revoked'
        Rails.logger.warn "[L] #002"
        ctx.deactivate!
      else
        Rails.logger.warn "[L] #003"
      end

    rescue Transport::NetworkError, Transport::ResponseError => e
      Rails.logger.warn "[L] #004"
    end
  end
end
