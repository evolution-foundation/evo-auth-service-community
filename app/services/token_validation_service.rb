# frozen_string_literal: true

class TokenValidationService
  class InvalidToken < StandardError; end
  class ExpiredToken < StandardError; end
  class TokenNotFound < StandardError; end

  CACHE_TTL = 5.minutes
  CACHE_KEY_PREFIX = "token_validation"

  attr_reader :token, :token_type

  def initialize(request)
    @request = request
    @used_token = extract_token
    @token_type = determine_token_type
    @token = nil
  end

  def validate!
    started_at = monotonic_now
    cache_status = "miss"
    raise TokenNotFound, "No authentication token provided" unless @used_token

    cached = Rails.cache.read(cache_key)

    if cached
      cache_status = "hit"
      # Verify token is still valid (not revoked, not expired)
      verify_token_not_revoked!
      log_validation_event(status: "ok", cache_status: cache_status, duration_ms: elapsed_ms(started_at))
      return cached
    end

    user_data = case @token_type
    when :bearer
      validate_bearer_token
    when :api_access_token
      validate_access_token
    else
      raise InvalidToken, "Unknown token type"
    end

    result = {
      user: user_data[:user],
      token: user_data[:token]
    }

    Rails.cache.write(cache_key, result, expires_in: CACHE_TTL)
    log_validation_event(status: "ok", cache_status: cache_status, duration_ms: elapsed_ms(started_at))
    result
  rescue StandardError => e
    log_validation_event(
      status: "error",
      cache_status: cache_status || "n/a",
      duration_ms: elapsed_ms(started_at),
      error_class: e.class.name
    )
    raise
  end

  def self.cache_key_for(token_string)
    "#{CACHE_KEY_PREFIX}/#{Digest::SHA256.hexdigest(token_string)}"
  end

  def self.invalidate_cache_for_token(token_string)
    Rails.cache.delete(cache_key_for(token_string))
  end

  def self.invalidate_cache_for_user(user)
    # Invalidate cache for all active bearer tokens
    Doorkeeper::AccessToken
      .where(resource_owner_id: user.id, revoked_at: nil)
      .where("expires_in IS NULL OR created_at + make_interval(secs => expires_in) > ?", Time.current)
      .pluck(:token)
      .each { |t| invalidate_cache_for_token(t) }

    # Invalidate cache for all access tokens owned by the user
    AccessToken
      .where(owner: user)
      .pluck(:token)
      .each { |t| invalidate_cache_for_token(t) }
  end

  private

  def cache_key
    self.class.cache_key_for(@used_token)
  end

  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def elapsed_ms(started_at)
    ((monotonic_now - started_at) * 1000).round(1)
  end

  def log_validation_event(status:, cache_status:, duration_ms:, error_class: nil)
    payload = [
      "TokenValidationPerformance",
      "status=#{status}",
      "token_type=#{@token_type || :unknown}",
      "cache=#{cache_status}",
      "duration_ms=#{duration_ms}"
    ]
    payload << "error=#{error_class}" if error_class

    if status == "ok"
      Rails.logger.info(payload.join(" "))
    else
      Rails.logger.warn(payload.join(" "))
    end
  end

  def verify_token_not_revoked!
    case @token_type
    when :bearer
      @token = Doorkeeper::AccessToken.by_token(@used_token)
      raise InvalidToken, "Invalid bearer token" unless @token
      raise ExpiredToken, "Token has expired" if @token.expired?
      raise InvalidToken, "Token has been revoked" if @token.revoked?
    when :api_access_token
      @token = AccessToken.find_by(token: @used_token)
      raise InvalidToken, "Invalid access token" unless @token
    end
  end

  def extract_token
    # Priority: Bearer > api_access_token
    bearer_token || api_access_token
  end

  def bearer_token
    auth_header = @request.headers["Authorization"]
    return unless auth_header&.start_with?("Bearer ")

    auth_header.split.last
  end

  def api_access_token
    @request.headers["api_access_token"] ||
    @request.headers["HTTP_API_ACCESS_TOKEN"] ||
    @request.headers[:api_access_token] ||
    @request.headers[:HTTP_API_ACCESS_TOKEN]
  end

  def determine_token_type
    return :bearer if bearer_token.present?
    return :api_access_token if api_access_token.present?

    nil
  end

  def validate_bearer_token
    @token = Doorkeeper::AccessToken.by_token(@used_token)
    raise InvalidToken, "Invalid bearer token" unless @token
    raise ExpiredToken, "Token has expired" if @token.expired?

    user = User.find(@token.resource_owner_id)

    {
      user: UserSerializer.full(user),
      token: TokenSerializer.oauth(@token, user)
    }
  end

  def validate_access_token
    @token = AccessToken.find_by(token: @used_token)
    raise InvalidToken, "Invalid access token" unless @token

    user = @token.issued_id.present? ? User.find(@token.issued_id) : @token.owner

    {
      user: UserSerializer.full(user),
      token: TokenSerializer.access_token(@token)
    }
  end
end
