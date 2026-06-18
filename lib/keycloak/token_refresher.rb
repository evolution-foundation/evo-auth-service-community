# frozen_string_literal: true

require 'net/http'
require 'json'

module Keycloak
  # Exchanges a Keycloak refresh_token for a new set of tokens.
  #
  # Usage:
  #   result = Keycloak::TokenRefresher.refresh(refresh_token: user.keycloak_refresh_token)
  #   # => { access_token:, id_token:, refresh_token:, expires_in:, refresh_expires_in: }
  #
  # Configuration (ENV):
  #   KEYCLOAK_ISSUER       — JWT issuer / public realm URL
  #   KEYCLOAK_INTERNAL_URL — internal Docker URL (falls back to KEYCLOAK_ISSUER)
  #   KEYCLOAK_CLIENT_ID    — client identifier
  #   KEYCLOAK_SSL_VERIFY   — set to "false" in development to skip SSL verification
  class TokenRefresher
    Error          = Class.new(StandardError)
    ExpiredError   = Class.new(Error)
    InvalidError   = Class.new(Error)

    def self.refresh(refresh_token:)
      new(refresh_token: refresh_token).refresh
    end

    def initialize(refresh_token:)
      @refresh_token = refresh_token
    end

    def refresh
      raise Error, "refresh_token is required" if @refresh_token.blank?

      uri      = URI("#{base_url}/protocol/openid-connect/token")
      http     = build_http(uri)
      request  = build_request(uri)
      response = http.request(request)

      body = JSON.parse(response.body)

      unless response.is_a?(Net::HTTPSuccess)
        error_code = body['error']
        description = body['error_description'] || response.body

        if error_code == 'invalid_grant'
          raise ExpiredError, "Keycloak refresh token is expired or invalid: #{description}"
        end

        raise Error, "Keycloak token refresh failed (HTTP #{response.code}): #{description}"
      end

      raise Error, "Keycloak response is missing access_token" unless body['access_token']

      {
        access_token:       body['access_token'],
        id_token:           body['id_token'],
        refresh_token:      body['refresh_token'],
        expires_in:         body['expires_in'],
        refresh_expires_in: body['refresh_expires_in']
      }
    rescue JSON::ParserError => e
      raise Error, "Invalid JSON from Keycloak token endpoint: #{e.message}"
    rescue Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout => e
      raise Error, "Could not reach Keycloak at #{base_url}: #{e.message}"
    end

    private

    def base_url
      ENV.fetch('KEYCLOAK_INTERNAL_URL') { ENV.fetch('KEYCLOAK_ISSUER') { raise Error, 'KEYCLOAK_ISSUER is not configured' } }
    end

    def client_id
      ENV.fetch('KEYCLOAK_CLIENT_ID') { raise Error, 'KEYCLOAK_CLIENT_ID is not configured' }
    end

    def build_request(uri)
      req = Net::HTTP::Post.new(uri.request_uri)
      req['Content-Type'] = 'application/x-www-form-urlencoded'
      req.body = URI.encode_www_form(
        grant_type:    'refresh_token',
        client_id:     client_id,
        refresh_token: @refresh_token
      )
      req
    end

    def build_http(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl      = (uri.scheme == 'https')
      http.verify_mode  = ssl_verify_mode
      http.open_timeout = 5
      http.read_timeout = 10
      http
    end

    def ssl_verify_mode
      if ENV['KEYCLOAK_SSL_VERIFY'] == 'false'
        OpenSSL::SSL::VERIFY_NONE
      else
        OpenSSL::SSL::VERIFY_PEER
      end
    end
  end
end
