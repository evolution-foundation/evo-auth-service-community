# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'oj'

module Licensing
  module Registration
    def self.init_register(instance_id:, tier:, version:, redirect_uri: nil)
      payload = { instance_id: instance_id, tier: tier, version: version }
      payload[:redirect_uri] = redirect_uri if redirect_uri.present?
      _snzd('/v1/register/init', payload)
    end

    def self.exchange_code(code:, instance_id:)
      _snzd('/v1/register/exchange', {
        authorization_code: code,
        instance_id:        instance_id
      })
    end

    def self.direct_register(tier:, email:, name:, instance_id:, version:, country: nil, city: nil)
      _snzd('/v1/register/direct', {
        tier:        tier,
        email:       email,
        name:        name,
        instance_id: instance_id,
        version:     version,
        country:     country,
        city:        city
      }.compact)
    end

    def self.geo_lookup(ip)
      return {} if ip.blank?

      base_url = Endpoint.resolve_url
      uri      = URI.parse("#{base_url}/api/geo")

      http              = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl       = uri.scheme == 'https'
      http.open_timeout  = Transport::TIMEOUT_SECONDS
      http.read_timeout  = Transport::TIMEOUT_SECONDS

      request = Net::HTTP::Get.new(uri.request_uri)
      request['Accept']          = 'application/json'
      request['X-Forwarded-For'] = ip

      response = http.request(request)
      return {} unless response.is_a?(Net::HTTPSuccess)

      Oj.load(response.body, mode: :compat)
    rescue StandardError
      {}
    end

    def self._snzd(path, payload)
      base_url = Endpoint.resolve_url
      uri      = URI.parse("#{base_url}#{path}")

      http              = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl       = uri.scheme == 'https'
      http.open_timeout  = Transport::TIMEOUT_SECONDS
      http.read_timeout  = Transport::TIMEOUT_SECONDS
      http.write_timeout = Transport::TIMEOUT_SECONDS

      request                  = Net::HTTP::Post.new(uri.request_uri)
      request['Content-Type']  = 'application/json'
      request['Accept']        = 'application/json'
      request.body             = Oj.dump(payload, mode: :compat)

      response = http.request(request)
      raise Transport::ResponseError.new(response.code.to_i, response.body) unless response.is_a?(Net::HTTPSuccess)

      Oj.load(response.body, mode: :compat)
    rescue Transport::ResponseError
      raise
    rescue => e
      raise Transport::NetworkError, "Network error contacting licensing server: #{e.message}"
    end

    private_class_method :_snzd
  end
end
