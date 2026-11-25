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

    # A pre-change job carries NO argument: it fails the chain check and exits
    # without rescheduling — that is the cleanup of the accumulated chains.
    # A tick superseded by a retried enqueue exits the same way.
    def perform(generation = nil, tick = nil)
      return unless Heartbeat.chain_alive?(generation) && Heartbeat.current_tick?(tick)

      ticking = true
      Heartbeat.ping
    ensure
      # $! is the in-flight exception during unwinding; nil means clean exit.
      # Only reschedule on success — an unexpected exception must not create
      # a runaway loop of failing jobs every INTERVAL seconds.
      Heartbeat.reschedule!(generation) if ticking && $!.nil?
    end
  end
end
