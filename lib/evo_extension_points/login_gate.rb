# frozen_string_literal: true

module EvoExtensionPoints
  # LoginGate extension point.
  #
  # Community default returns :allow; the auth-service performs no
  # pre-login check beyond what Devise already enforces. A consumer
  # overrides via:
  #   EvoExtensionPoints.replace(:login_gate) { |user, **context| ... }
  #
  # Strict accepted return shapes at v1.0.0:
  # - :allow                            (login proceeds)
  # - [:deny, reason_symbol]            (login denied; reason logged
  #                                      but never shown to the user)
  # Any other return value raises InvalidReturnError and the
  # auth-service fail-closes the login. Exceptions raised by the
  # consumer block are caught, logged at ERROR, and also fail-close
  # with denial_reason :gate_exception.
  #
  # See EXTENSION_POINTS.md at the repository root.
  module LoginGate
    VERSION = '1.0.0'

    class InvalidReturnError < StandardError
      attr_reader :returned

      def initialize(returned)
        @returned = returned
        super("login_gate override returned unsupported value: #{returned.inspect}")
      end
    end

    class << self
      def check(user, **context)
        impl = EvoExtensionPoints.impl_for(:login_gate)
        return :allow unless impl

        result = safe_call(impl, user, **context)
        validate!(result)
      rescue InvalidReturnError => e
        log_invalid(e)
        [:deny, :gate_invalid_return]
      end

      private

      def safe_call(impl, user, **context)
        impl.call(user, **context)
      rescue StandardError => e
        log_exception(e)
        return [:deny, :gate_exception]
      end

      def validate!(result)
        return :allow if result == :allow
        return result if deny_shape?(result)

        raise InvalidReturnError, result
      end

      def deny_shape?(result)
        result.is_a?(Array) &&
          result.length == 2 &&
          result.first == :deny &&
          result.last.is_a?(Symbol)
      end

      def log_invalid(error)
        return unless defined?(::Rails) && ::Rails.respond_to?(:logger) && ::Rails.logger

        ::Rails.logger.error(
          "[EvoExtensionPoints::LoginGate] invalid return; failing closed:" \
          " #{error.returned.inspect}"
        )
      end

      def log_exception(error)
        return unless defined?(::Rails) && ::Rails.respond_to?(:logger) && ::Rails.logger

        ::Rails.logger.error(
          "[EvoExtensionPoints::LoginGate] override raised; failing closed:" \
          " #{error.class}: #{error.message}"
        )
        if ::Rails.logger.respond_to?(:error) && error.backtrace
          ::Rails.logger.error(error.backtrace.first(10).join("\n"))
        end
      end
    end
  end
end
