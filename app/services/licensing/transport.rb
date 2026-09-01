# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'oj'

module Licensing
  class Transport
    class NetworkError < StandardError; end

    class ResponseError < StandardError
      attr_reader :status_code, :body, :retry_after

      # retry_after: seconds the server asked us to hold off (Retry-After
      # header), nil when absent — RetryPolicy honours it as a floor.
      def initialize(status_code, body, retry_after: nil)
        @status_code = status_code
        @body        = body
        @retry_after = retry_after
        super("Licensing server responded with HTTP #{status_code}: #{body}")
      end
    end

    TIMEOUT_SECONDS = 10

    def initialize(base_url:, api_key:)
      raise ArgumentError, 'api_key cannot be nil or empty' if api_key.nil? || api_key.strip.empty?

      @base_url = base_url
      @api_key  = api_key
    end

    def post_signed(path, payload)
      body = Oj.dump(payload, mode: :compat)
      headers = _ti.merge(
        'X-Api-Key'   => @api_key,
        'X-Signature' => Hmac.sign_payload(body, @api_key)
      )
      _cq(path, body, headers)
    end

    def post_unsigned(path, payload)
      body = Oj.dump(payload, mode: :compat)
      _cq(path, body, _ti)
    end

    def get_unsigned(path, params = {})
      _u24(path, params)
    end

    private

    def _ti
      { 'Content-Type' => 'application/json', 'Accept' => 'application/json' }
    end

    def _cq(path, body, headers)
      uri  = URI.parse("#{@base_url}#{path}")
      http = _awh4(uri)

      request = Net::HTTP::Post.new(uri.request_uri)
      headers.each { |k, v| request[k] = v }
      request.body = body

      _8n(http, request)
    rescue NetworkError, ResponseError
      raise
    rescue => e
      raise NetworkError, "Network error contacting licensing server: #{e.message}"
    end

    def _u24(path, params)
      uri = URI.parse("#{@base_url}#{path}")
      uri.query = URI.encode_www_form(params) unless params.empty?
      http = _awh4(uri)

      request = Net::HTTP::Get.new(uri.request_uri)
      _ti.each { |k, v| request[k] = v }

      _8n(http, request)
    rescue NetworkError, ResponseError
      raise
    rescue => e
      raise NetworkError, "Network error contacting licensing server: #{e.message}"
    end

    def _awh4(uri)
      http              = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl      = uri.scheme == 'https'
      http.open_timeout = TIMEOUT_SECONDS
      http.read_timeout = TIMEOUT_SECONDS
      http.write_timeout = TIMEOUT_SECONDS
      http
    end

    def _8n(http, request)
      response = http.request(request)
      unless response.is_a?(Net::HTTPSuccess)
        raise ResponseError.new(response.code.to_i, response.body,
                                retry_after: parse_retry_after(response['Retry-After']))
      end

      _wju(response.body)
    rescue ResponseError
      raise
    rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, Errno::ECONNREFUSED,
           Errno::ECONNRESET, SocketError, EOFError => e
      raise NetworkError, "Network error contacting licensing server: #{e.message}"
    end

    def _wju(body)
      Oj.load(body, mode: :compat)
    rescue Oj::ParseError, JSON::ParserError => e
      raise NetworkError, "Invalid JSON response from licensing server: #{e.message}"
    end

    # Delta-seconds form only; the HTTP-date form is not worth parsing here —
    # nil just means the backoff computes its own window.
    def parse_retry_after(value)
      seconds = value.to_s.strip
      return nil unless seconds.match?(/\A\d+\z/)

      seconds.to_i
    end
  end
end
