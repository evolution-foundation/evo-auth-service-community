# frozen_string_literal: true

module Licensing
  module Heartbeat
    INTERVAL = 5.minutes
    # Fraction of INTERVAL randomized both ways on every reschedule, so a fleet
    # of boxes booted together does not tick in lockstep against the server.
    JITTER = 0.2
    GENERATION_KEY = 'licensing:heartbeat_generation'

    # The ONLY way a heartbeat chain starts. Every scheduling site used to
    # start its OWN self-rescheduling chain, and Sidekiq persists scheduled
    # jobs across restarts — so each boot added one more immortal chain per
    # box (the observed flood). Rotating the generation makes every previous
    # chain exit on its next tick instead of rescheduling.
    def self.schedule!(wait: next_interval)
      generation = SecureRandom.uuid
      Rails.cache.write(GENERATION_KEY, generation)
      HeartbeatJob.set(wait: wait).perform_later(generation)
      generation
    end

    def self.current_generation
      Rails.cache.read(GENERATION_KEY)
    end

    # A chain survives ONLY while it matches the current generation. A nil
    # current generation (cache evicted) adopts the caller's — liveness beats
    # strictness there: killing the last chain would silence the heartbeat
    # entirely — but a MISMATCH always kills, which is what collapses the
    # accumulated legacy chains after the image updates.
    def self.chain_alive?(generation)
      return false if generation.nil?

      current = current_generation
      if current.nil?
        Rails.cache.write(GENERATION_KEY, generation)
        return true
      end
      current == generation
    end

    def self.next_interval
      INTERVAL * (1 + (JITTER * ((2 * rand) - 1)))
    end

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
