# frozen_string_literal: true

module Licensing
  module Deactivation
    def self.deactivate!(ctx: Runtime.context, store: nil)
      return unless ctx&.active?

      begin
        transport = Transport.new(base_url: Endpoint.resolve_url, api_key: ctx.api_key)
        transport.post_signed('/v1/deactivate', {
          instance_id: ctx.instance_id,
          version:     Activation::VERSION
        })
        Rails.logger.info "[L] #001"

      rescue Transport::NetworkError, Transport::ResponseError => e
        Rails.logger.warn "[L] #002"

      ensure
        ctx.deactivate!
        Rails.logger.info "[L] #003"
      end
    end
  end
end
