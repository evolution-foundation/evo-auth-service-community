# frozen_string_literal: true

module Licensing
  module Heartbeat
    INTERVAL = 5.minutes
    # Fraction of INTERVAL randomized both ways on every reschedule, so a fleet
    # of boxes booted together does not tick in lockstep against the server.
    JITTER = 0.2
    GENERATION_KEY = 'licensing:heartbeat_generation'
    TICK_KEY = "licensing:heartbeat_tick"
    RESCHEDULE_RETRY_BASE = 5.seconds

    # The only way a chain starts. Rotating the generation makes every previous
    # chain exit on its next tick instead of rescheduling.
    def self.schedule!(wait: next_interval)
      generation = SecureRandom.uuid
      Rails.cache.write(GENERATION_KEY, generation)
      HeartbeatJob.set(wait: wait).perform_later(generation)
      generation
    end

    # Queues the next tick of a live chain. When the enqueue fails (Redis down)
    # the retry is held in this process, because nothing queued is left to
    # carry the chain; the wait doubles up to INTERVAL.
    #
    # Each tick carries an id stored before the enqueue: if a failed enqueue
    # had in fact been accepted, the retry's newer id makes that tick exit
    # instead of growing a second chain.
    def self.reschedule!(generation, attempt: 0)
      return unless Runtime.context&.active? && chain_alive?(generation)

      tick = SecureRandom.uuid
      Rails.cache.write(TICK_KEY, tick)
      job = HeartbeatJob.new(generation, tick)
      return if job.enqueue(wait: next_interval)

      Rails.logger.warn "[Licensing::Heartbeat] reschedule refused (#{job.enqueue_error&.message || 'no error given'}) — retrying in-process"
      retry_reschedule(generation, attempt)
    rescue StandardError => e
      Rails.logger.warn "[Licensing::Heartbeat] reschedule failed (#{e.class}) — retrying in-process"
      retry_reschedule(generation, attempt)
    end

    def self.retry_reschedule(generation, attempt)
      delay = [ RESCHEDULE_RETRY_BASE * (2**attempt), INTERVAL ].min
      retry_later(delay) { reschedule!(generation, attempt: attempt + 1) }
    end

    # The retry runs on a concurrent-ruby thread, outside any request or job,
    # so it enters the Rails executor like a job would.
    def self.retry_later(delay, &block)
      Concurrent::ScheduledTask.execute(delay.to_f) { Rails.application.executor.wrap(&block) }
    end

    # A tick from before ids existed (or from schedule!) carries none and
    # passes. A nil current id (cache evicted) adopts the caller's, as
    # chain_alive? does with the generation.
    def self.current_tick?(tick)
      return true if tick.nil?

      current = Rails.cache.read(TICK_KEY)
      if current.nil?
        Rails.cache.write(TICK_KEY, tick)
        return true
      end
      current == tick
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
