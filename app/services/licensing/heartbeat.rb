# frozen_string_literal: true

module Licensing
  module Heartbeat
    INTERVAL = 5.minutes
    # Fraction of INTERVAL randomized both ways on every reschedule, so a fleet
    # of boxes booted together does not tick in lockstep against the server.
    JITTER = 0.2
    GENERATION_KEY = 'licensing:heartbeat_generation'

    # The only way a chain starts. Rotating the generation makes every previous
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

    # A nil current generation (cache evicted) adopts the caller's — killing the
    # last chain would silence the heartbeat. A mismatch always kills.
    def self.chain_alive?(generation)
      return false if generation.nil?

      current = current_generation
      if current.nil?
        Rails.cache.write(GENERATION_KEY, generation)
        return true
      end
      current == generation
    end

    # Never below the jittered INTERVAL, never inside the backoff window a
    # refused ping left behind — that window is what makes the interval grow.
    def self.next_interval(now: Time.current)
      jittered = INTERVAL * (1 + (JITTER * ((2 * rand) - 1)))
      cool_down = RetryPolicy.seconds_until_open(window: RetryPolicy::HEARTBEAT_WINDOW, now: now)
      [jittered, cool_down].max
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

      RetryPolicy.record_success!(window: RetryPolicy::HEARTBEAT_WINDOW)

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
      wait = RetryPolicy.record_failure!(
        window:      RetryPolicy::HEARTBEAT_WINDOW,
        base_wait:   INTERVAL,
        retry_after: e.try(:retry_after)
      )
      Rails.logger.warn "[L] #004"
      Rails.logger.warn "[Licensing::Heartbeat] ping refused — next tick in #{wait.to_i}s"
    end
  end
end
