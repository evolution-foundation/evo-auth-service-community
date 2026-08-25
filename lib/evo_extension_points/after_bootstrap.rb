# frozen_string_literal: true

module EvoExtensionPoints
  # AfterBootstrap extension point.
  #
  # Runs INSIDE the /setup bootstrap transaction, immediately after the first
  # admin user and its global role are created. Community default is a no-op.
  # Override via:
  #   EvoExtensionPoints.replace(:after_bootstrap) { |user:, payload:| ... }
  #
  # user    — the freshly created, persisted admin User.
  # payload — an OPAQUE hash forwarded verbatim from the request's
  #           `extension_payload`. The community assigns it no meaning; the
  #           consumer validates and interprets it.
  #
  # Error policy: this dispatcher does NOT rescue. The call site is inside the
  # bootstrap transaction, so an exception from the consumer block rolls the
  # whole install back — atomic by design. The consumer owns any internal
  # fail-open/fail-closed policy.
  #
  # Return contract (1.1.0): :degraded means the consumer ran but could not
  # finish. Anything else is :ok — including a 1.0.0-era consumer's incidental
  # return value and no consumer at all. See EXTENSION_POINTS.md section 4.
  module AfterBootstrap
    VERSION = '1.1.0'

    # The only value that means "ran, but did not finish".
    DEGRADED = :degraded

    class << self
      # @return [Symbol] :ok or :degraded — never nil, so callers branch without
      #   a nil check.
      def run(user:, payload: {})
        impl = EvoExtensionPoints.impl_for(:after_bootstrap)
        return :ok unless impl

        impl.call(user: user, payload: payload) == DEGRADED ? DEGRADED : :ok
      end
    end
  end
end
