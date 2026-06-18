# frozen_string_literal: true

require 'net/http'
require 'json'

module Keycloak
  # Exchanges a PKCE authorization code for a Keycloak access token
  # server-side, so the browser never connects directly to Keycloak.
  #
  # Usage:
  #   access_token = Keycloak::CodeExchanger.exchange(
  #     code:          params[:code],
  #     code_verifier: params[:code_verifier],
  #     redirect_uri:  params[:redirect_uri],
  #   )
  #
  # Configuration (ENV):
  #   KEYCLOAK_ISSUER       — JWT issuer / public realm URL (e.g. https://localhost:8443/realms/organization)
  #   KEYCLOAK_INTERNAL_URL — internal Docker URL for HTTP calls (e.g. https://keycloak:8443/realms/organization)
  #                           Falls back to KEYCLOAK_ISSUER if not set.
  #   KEYCLOAK_CLIENT_ID    — public client ID registered in Keycloak
  #   KEYCLOAK_SSL_VERIFY   — set to "false" in development to skip SSL verification
  class CodeExchanger
    Error = Class.new(StandardError)

    def self.exchange(code:, redirect_uri:, code_verifier: nil)
      new(code: code, code_verifier: code_verifier, redirect_uri: redirect_uri).exchange
    end

    def initialize(code:, redirect_uri:, code_verifier: nil)
      @code          = code
      @code_verifier = code_verifier
      @redirect_uri  = redirect_uri
    end

    def exchange
      unless @code_verifier.present?
        Rails.logger.warn("[Keycloak::CodeExchanger] PKCE code_verifier not provided — exchange proceeds without PKCE. " \
                          "Consider using PKCE for enhanced security.")
      end

      uri      = URI("#{base_url}/protocol/openid-connect/token")
      http     = build_http(uri)
      request  = build_request(uri)

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        raise Error, "Keycloak token exchange failed (HTTP #{response.code}): #{response.body}"
      end

      data = JSON.parse(response.body)
      raise(Error, "Keycloak response is missing access_token") unless data['access_token']
      {
        access_token:  data['access_token'],
        id_token:      data['id_token'],
        refresh_token: data['refresh_token'],
        expires_in:    data['expires_in'],
        refresh_expires_in: data['refresh_expires_in']
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
      params = {
        grant_type:   'authorization_code',
        client_id:    client_id,
        code:         @code,
        redirect_uri: @redirect_uri
      }
      params[:code_verifier] = @code_verifier if @code_verifier.present?
      req.body = URI.encode_www_form(params)
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
