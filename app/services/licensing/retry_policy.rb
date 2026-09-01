# frozen_string_literal: true

module Licensing
  # Cool-down for client calls to the licensing server: without it a box that
  # cannot activate re-attempts on every login with no memory of the refusal.
  # Each caller names its own window so a refused heartbeat does not gate
  # activation. State lives in Rails.cache, shared by the box's processes.
  module RetryPolicy
    ACTIVATION_WINDOW = 'licensing:activation_backoff'
    HEARTBEAT_WINDOW  = 'licensing:heartbeat_backoff'

    BASE_WAIT = 30.seconds
    MAX_WAIT  = 30.minutes
    # Fraction of the wait randomized both ways so a fleet rebooted together
    # does not re-synchronize its retries.
    JITTER = 0.2
    # Past this the doubling only builds a bignum the cap throws away.
    MAX_EXPONENT = 16
    # Slack on the window key's TTL so it never expires before it opens.
    TTL_SLACK = 1.minute

    module_function

    def allow_attempt?(window: ACTIVATION_WINDOW, now: Time.current)
      seconds_until_open(window: window, now: now).zero?
    end

    # Seconds left on the window, 0 when open. A caller that paces itself (the
    # heartbeat chain) uses this to push its next tick out instead of polling.
    def seconds_until_open(window: ACTIVATION_WINDOW, now: Time.current)
      opens_at = Rails.cache.read(window_key(window))
      return 0 if opens_at.nil? || now >= opens_at

      opens_at - now
    end

    # retry_after is the server's Retry-After in seconds, honoured as a floor.
    # Returns the wait applied to the window.
    def record_failure!(window: ACTIVATION_WINDOW, base_wait: BASE_WAIT, now: Time.current, retry_after: nil)
      wait = base_wait * (2**(bump_failures(window) - 1))
      # Jitter BEFORE the cap: capping first lets the +20% push the real window
      # past MAX_WAIT, so the constant would not be the maximum it claims.
      wait = [wait * (1 + (JITTER * ((2 * rand) - 1))), MAX_WAIT].min
      wait = [wait, retry_after].max if retry_after

      # TTL from the wait, not from MAX_WAIT: a longer Retry-After would expire
      # the key before the window opened, reopening it early.
      Rails.cache.write(window_key(window), now + wait, expires_in: wait + TTL_SLACK)
      wait
    end

    def record_success!(window: ACTIVATION_WINDOW)
      Rails.cache.delete(window_key(window))
      Rails.cache.delete(failures_key(window))
    end

    # increment is atomic on the Redis store; a read-modify-write here loses
    # increments across the box's processes and flattens the ladder.
    def bump_failures(window)
      Rails.cache
           .increment(failures_key(window), 1, expires_in: MAX_WAIT * 2)
           .to_i.clamp(1, MAX_EXPONENT)
    end

    def window_key(window)
      "#{window}:opens_at"
    end

    def failures_key(window)
      "#{window}:failures"
    end

    private_class_method :bump_failures, :window_key, :failures_key
  end
end
