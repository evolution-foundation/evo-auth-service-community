# frozen_string_literal: true

module Licensing
  # Cool-down for client calls to the licensing server. Without it a box that
  # cannot activate re-attempts on every trigger (each login re-runs the setup
  # concern) with no memory of the last refusal — a fleet of those melts the
  # server's rate limiter and the 429s then feed the loop. State lives in
  # Rails.cache so every process of the box shares one window; it resets on
  # the first successful activation.
  module RetryPolicy
    CACHE_KEY = 'licensing:activation_backoff'
    BASE_WAIT = 30.seconds
    MAX_WAIT  = 30.minutes
    # Fraction of the wait randomized both ways so a fleet rebooted together
    # does not re-synchronize its retries.
    JITTER = 0.2

    module_function

    def allow_attempt?(now: Time.current)
      state = Rails.cache.read(CACHE_KEY)
      return true if state.nil?

      next_attempt_at = state[:next_attempt_at]
      next_attempt_at.nil? || now >= next_attempt_at
    end

    # @return [ActiveSupport::Duration, Numeric] the wait applied to the window
    def record_failure!(now: Time.current)
      state    = Rails.cache.read(CACHE_KEY) || {}
      failures = state[:failures].to_i + 1

      wait = [BASE_WAIT * (2**(failures - 1)), MAX_WAIT].min
      wait *= 1 + (JITTER * ((2 * rand) - 1))

      Rails.cache.write(
        CACHE_KEY,
        { failures: failures, next_attempt_at: now + wait },
        expires_in: MAX_WAIT * 2
      )
      wait
    end

    def record_success!
      Rails.cache.delete(CACHE_KEY)
    end
  end
end
