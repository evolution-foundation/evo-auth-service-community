# frozen_string_literal: true

module EvoExtensionPoints
  # ExtraSetupSteps capability query.
  #
  # Backs the `extra_setup_steps` boolean on GET /setup/status. Tells the
  # frontend Setup wizard whether a consumer contributes extra steps after the
  # account step. Community default is false — a pure community install has a
  # single-step wizard. Replaces the old enterprise whitelabel-table probe, so
  # the community no longer names any enterprise table. Override via:
  #   EvoExtensionPoints.replace(:extra_setup_steps) { true }
  #
  # Fail-soft: any error from the consumer block degrades to false so the wizard
  # never traps on a broken probe.
  module ExtraSetupSteps
    VERSION = '1.0.0'

    class << self
      def enabled?
        impl = EvoExtensionPoints.impl_for(:extra_setup_steps)
        return false unless impl

        !!impl.call
      rescue StandardError => e
        if defined?(::Rails) && ::Rails.respond_to?(:logger) && ::Rails.logger
          ::Rails.logger.warn(
            "[EvoExtensionPoints::ExtraSetupSteps] probe raised; defaulting to false: #{e.message}"
          )
        end
        false
      end
    end
  end
end
