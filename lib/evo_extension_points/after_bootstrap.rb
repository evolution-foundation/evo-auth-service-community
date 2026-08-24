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
  # Return contract (1.1.0, CRM-262): the consumer MAY report whether it actually
  # completed. Up to 1.0.0 this dispatcher discarded the block's return value and
  # always answered nil, so a consumer that failed FAIL-SOFT — the enterprise
  # overlay is deliberately fail-soft, since raising here would roll the whole
  # install back — had no way to say so. /setup then answered "Installation
  # completed successfully" over a box left without membership, without its first
  # account and without roles.
  #
  # Recognised returns:
  #   :degraded — the consumer ran but could not finish; the caller should say so
  #   anything else — treated as :ok, so a 1.0.0-era consumer (which returns
  #                   whatever its last expression happened to be) keeps working
  #                   exactly as before
  #
  # A community install with no consumer registered also gets :ok — nothing was
  # pending, so nothing is degraded, and the community response stays identical
  # to what it was before this change.
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
