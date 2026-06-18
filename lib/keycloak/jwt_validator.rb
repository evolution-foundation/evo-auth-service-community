# frozen_string_literal: true

require 'net/http'
require 'openssl'
require 'json'

module Keycloak
  # Validates Keycloak-issued JWTs against the realm's JWKS endpoint.
  #
  # Usage:
  #   claims = Keycloak::JwtValidator.verify(raw_token)  # => Hash or raises Error
  #
  # Configuration (ENV):
  #   KEYCLOAK_ISSUER — e.g. https://localhost:8443/realms/organization
  #
  # JWKS responses are cached in-process for JWKS_CACHE_TTL seconds.
  # The cache is mutex-protected for thread safety.
  class JwtValidator
    Error = Class.new(StandardError)

    JWKS_CACHE_TTL = 300 # seconds

    class << self
      def verify(token)
        # Decode without iss verification first to get claims
        payload, = JWT.decode(
          token,
          nil,
          true,
          algorithms: %w[RS256 RS384 RS512],
          verify_iss: false
        ) { |header, _payload| resolve_key(header['kid']) }

        # Manually verify iss against all accepted issuers (public + internal)
        token_iss = payload['iss']
        unless accepted_issuers.include?(token_iss)
          raise Error, "Invalid issuer '#{token_iss}'. Expected one of: #{accepted_issuers.join(', ')}"
        end

        # Explicit expiration check with human-readable message
        if payload['exp'].present?
          exp_time = Time.at(payload['exp'].to_i).utc
          if exp_time <= Time.now.utc
            raise Error, "Token has expired at #{exp_time.iso8601} (current time: #{Time.now.utc.iso8601})"
          end
        else
          raise Error, "Token is missing the 'exp' claim"
        end

        # Not-before check
        if payload['nbf'].present?
          nbf_time = Time.at(payload['nbf'].to_i).utc
          if nbf_time > Time.now.utc
            raise Error, "Token is not valid before #{nbf_time.iso8601} (current time: #{Time.now.utc.iso8601})"
          end
        end

        payload
      rescue JWT::DecodeError => e
        raise Error, e.message
      end

      private

      def issuer
        ENV.fetch('KEYCLOAK_ISSUER') do
          raise Error, 'KEYCLOAK_ISSUER is not configured'
        end
      end

      # Returns all accepted issuers: the public one and the internal Docker one (if different)
      def accepted_issuers
        issuers = [issuer]
        internal = ENV['KEYCLOAK_INTERNAL_URL'].presence
        issuers << internal if internal && internal != issuer
        issuers
      end

      def resolve_key(kid)
        key_data = fetch_jwks.find { |k| k['kid'] == kid }
        return nil unless key_data

        JWT::JWK.import(key_data).public_key
      rescue StandardError => e
        Rails.logger.error("[Keycloak::JwtValidator] key resolution failed: #{e.message}")
        nil
      end

      def fetch_jwks
        mutex.synchronize do
          if @jwks.nil? || stale?
            @jwks = load_jwks
            @fetched_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          end
        end
        @jwks
      end

      def jwks_base_url
        ENV['KEYCLOAK_INTERNAL_URL'].presence || issuer
      end

      def load_jwks
        uri = URI("#{jwks_base_url}/protocol/openid-connect/certs")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == 'https')
        http.verify_mode = ssl_verify_mode
        http.open_timeout = 5
        http.read_timeout = 5

        response = http.get(uri.request_uri)
        JSON.parse(response.body)['keys'] || []
      rescue StandardError => e
        Rails.logger.error("[Keycloak::JwtValidator] JWKS fetch failed: #{e.message}")
        @jwks || []
      end

      def ssl_verify_mode
        if ENV['KEYCLOAK_SSL_VERIFY'] == 'false'
          OpenSSL::SSL::VERIFY_NONE
        else
          OpenSSL::SSL::VERIFY_PEER
        end
      end

      def stale?
        return true if @fetched_at.nil?

        Process.clock_gettime(Process::CLOCK_MONOTONIC) - @fetched_at > JWKS_CACHE_TTL
      end

      def mutex
        @mutex ||= Mutex.new
      end
    end
  end
end
