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

    # Jobs already sitting in Redis from before this change carry NO argument:
    # they fail the chain check and exit without rescheduling — that silent
    # death is the cleanup of the accumulated chains, not a bug.
    def perform(generation = nil)
      return unless Heartbeat.chain_alive?(generation)

      Heartbeat.ping
    ensure
      # $! is the in-flight exception during unwinding; nil means clean exit.
      # Only reschedule on success — an unexpected exception must not create
      # a runaway loop of failing jobs every INTERVAL seconds.
      if $!.nil? && Runtime.context&.active? && Heartbeat.chain_alive?(generation)
        self.class.set(wait: Heartbeat.next_interval).perform_later(generation)
      end
    end
  end
end
