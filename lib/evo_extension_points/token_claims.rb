# frozen_string_literal: true

module EvoExtensionPoints
  # TokenClaims extension point.
  #
  # Community default returns an empty hash; the auth-service emits no
  # extra claims beyond what devise_token_auth already produces. A
  # consumer overrides via:
  #   EvoExtensionPoints.replace(:token_claims) { |user| { ... } }
  #
  # Reserved JWT keys (iss, sub, aud, exp, iat, nbf, jti) MUST NOT be
  # overwritten by a consumer.
  # - In production / staging: conflicting reserved keys are dropped
  #   from the consumer hash and the auth-service logs at ERROR with
  #   the offending key list. Token emission proceeds with the
  #   auth-service-owned values.
  # - In development / test: the same merge raises ReservedKeyError so
  #   the violation is caught in CI before it reaches production.
  #
  # See EXTENSION_POINTS.md at the repository root.
  module TokenClaims
    VERSION = '1.0.0'

    RESERVED_JWT_KEYS = %w[iss sub aud exp iat nbf jti].freeze

    class ReservedKeyError < StandardError
      attr_reader :reserved_keys

      def initialize(keys)
        @reserved_keys = keys
        super("consumer override returned reserved JWT keys: #{keys.inspect}")
      end
    end

    class << self
      def claims_for(user)
        impl = EvoExtensionPoints.impl_for(:token_claims)
        raw = impl ? impl.call(user) : {}
        sanitize(raw)
      end

      private

      def sanitize(hash)
        return {} if hash.nil? || hash.empty?

        offending = hash.keys.map(&:to_s) & RESERVED_JWT_KEYS
        return hash if offending.empty?

        if strict_env?
          raise ReservedKeyError, offending
        else
          if defined?(::Rails) && ::Rails.respond_to?(:logger) && ::Rails.logger
            ::Rails.logger.error(
              "[EvoExtensionPoints::TokenClaims] consumer override returned" \
              " reserved JWT keys; dropping: #{offending.inspect}"
            )
          end
          hash.reject { |k, _| RESERVED_JWT_KEYS.include?(k.to_s) }
        end
      end

      def strict_env?
        return false unless defined?(::Rails) && ::Rails.respond_to?(:env) && ::Rails.env

        ::Rails.env.development? || ::Rails.env.test?
      end
    end
  end
end
