# frozen_string_literal: true

module Licensing
  # Runs Licensing::Setup.perform in background.
  #
  # The licensing handshake is best-effort: a self-hosted install must never
  # be blocked by an outage on our licensing server. This job retries on
  # transient transport errors and gives up silently after a few attempts —
  # the heartbeat path will retry later when the server comes back.
  class SetupJob < ApplicationJob
    queue_as :licensing
    discard_on StandardError

    # Reschedule cadence when the licensing server is unreachable.
    # Five attempts at growing intervals — total ~5 minutes — then we give up
    # and let the heartbeat path pick it up later.
    RETRY_WAITS = [10.seconds, 30.seconds, 1.minute, 2.minutes, 5.minutes].freeze

    def perform(email:, name:, client_ip: nil, attempt: 0)
      return if Runtime.context&.active?

      store       = Store.new
      instance_id = store.load_or_create_instance_id

      ok = Setup.perform(
        email:       email,
        name:        name,
        instance_id: instance_id,
        version:     Activation::VERSION,
        client_ip:   client_ip
      )

      return if ok
      return if attempt >= RETRY_WAITS.size - 1

      self.class
          .set(wait: RETRY_WAITS[attempt])
          .perform_later(email: email, name: name, client_ip: client_ip, attempt: attempt + 1)
    end
  end
end
