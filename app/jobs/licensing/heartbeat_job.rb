# frozen_string_literal: true

module Licensing
  # ActiveJob that periodically sends a heartbeat to the licensing server.
  # Self-reschedules via ensure so the interval continues while the license is active.
  #
  # Uses discard_on StandardError so unexpected failures never flood the dead-letter
  # queue — the ensure block reschedules regardless of success or failure.
  class HeartbeatJob < ApplicationJob
    queue_as :licensing
    discard_on StandardError

    def perform
      Heartbeat.ping
    ensure
      # $! is the in-flight exception during unwinding; nil means clean exit.
      # Only reschedule on success — an unexpected exception must not create
      # a runaway loop of failing jobs every INTERVAL seconds.
      if $!.nil? && Runtime.context&.active?
        self.class.set(wait: Heartbeat::INTERVAL).perform_later
      end
    end
  end
end
