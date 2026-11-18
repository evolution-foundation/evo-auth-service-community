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

    # Reschedule cadence when the licensing server is unreachable: five
    # attempts, then we give up and let the heartbeat path pick it up later.
    # Each step is a floor — the retry also waits out the backoff window the
    # failure just opened, or it would find the window closed and end the chain.
    RETRY_WAITS = [10.seconds, 30.seconds, 1.minute, 2.minutes, 5.minutes].freeze

    def perform(email:, name:, client_ip: nil, attempt: 0, key_digest: nil)
      return if Runtime.context&.active?

      store = Store.new
      # Another process (the web's /setup/activate, a login) may have activated
      # the license since the chain began; registering again would replace its key.
      return if attempt.positive? && stored_key_digest(store) != key_digest

      unless RetryPolicy.allow_attempt?
        # A login starts a new chain once the window opens; a retry waits for it.
        # The floor keeps a retry that lands a hair early from rescheduling in a loop.
        if attempt.positive?
          reschedule([ RetryPolicy.seconds_until_open, 1.second ].max,
                     email: email, name: name, client_ip: client_ip, attempt: attempt, key_digest: key_digest)
        end
        return
      end

      key_digest  = stored_key_digest(store) if attempt.zero?
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

      reschedule([ RETRY_WAITS[attempt], RetryPolicy.seconds_until_open ].max,
                 email: email, name: name, client_ip: client_ip, attempt: attempt + 1, key_digest: key_digest)
    end

    private

    def reschedule(wait, **args)
      self.class.set(wait: wait).perform_later(**args)
    end

    # A digest, not the key: job arguments are stored in the queue.
    def stored_key_digest(store)
      key = store.load_runtime_data&.dig("k")
      key && Digest::SHA256.hexdigest(key)[0, 16]
    end
  end
end
