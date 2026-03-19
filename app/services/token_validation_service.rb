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
      accounts: user_data[:accounts],
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

    user = User.includes(account_users: [ :role, :account_custom_role ]).find(@token.resource_owner_id)

    {
      user: UserSerializer.full(user),
      accounts: serialize_accounts(user),
      token: TokenSerializer.oauth(@token, user)
    }
  end

  def validate_access_token
    @token = AccessToken.find_by(token: @used_token)
    raise InvalidToken, "Invalid access token" unless @token

    user = resolve_user_from_access_token(@token)

    # When api_access_token is linked to an Account, return only that account
    # This allows the token to implicitly identify the account without requiring account-id header
    accounts = if @token.owner_type == "Account"
      # Token is linked to a specific account - return only that account
      account = @token.owner
      [ AccountSerializer.full(
        account,
        user: user,
        include_settings: true,
        include_attributes: true,
        include_role: true
      ) ]
    else
      # Token is linked to a User - return all user's accounts (legacy behavior)
      serialize_accounts(user)
    end

    {
      user: UserSerializer.full(user),
      accounts: accounts,
      token: TokenSerializer.access_token(@token),
      token_account_id: @token.owner_type == "Account" ? @token.owner_id : nil
    }
  end

  def resolve_user_from_access_token(access_token)
    case access_token.owner_type
    when "Account"
      # Use issued_id to get the user who created the token for this account
      if access_token.issued_id.present?
        User.includes(account_users: [ :role, :account_custom_role ]).find(access_token.issued_id)
      else
        # Fallback for old tokens without issued_id
        access_token.owner.users.includes(account_users: [ :role, :account_custom_role ]).first
      end
    else
      access_token.owner
    end
  end

  def serialize_accounts(user)
    return [] unless user

    total_start = Time.current
    query_count = 0

    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
      query_count += 1
    end

    begin
      load_start = Time.current
      accounts = user.accounts.active.includes(
        account_users: [
          :role,
          :account_custom_role
        ]
      )
      accounts_count = accounts.count
      load_time = (Time.current - load_start) * 1000
      load_queries = query_count

      Rails.logger.info "[TokenValidationService] serialize_accounts: Loaded #{accounts_count} accounts in #{load_time.round(2)}ms (#{load_queries} queries)"

      serialized = accounts.map.with_index do |account, index|
        account_start = Time.current
        account_query_before = query_count
        timings = {}

        # Find preloaded account_user to avoid role_data query
        account_user = user.account_users.find { |au| au.account_id == account.id }

        result = AccountSerializer.full(
          account,
          user: user,
          account_user: account_user,
          settings: true,
          custom_attributes: true,
          include_role: true,
          _timings: timings
        )

        account_queries = query_count - account_query_before
        account_time = (Time.current - account_start) * 1000

        Rails.logger.info "[TokenValidationService] serialize_accounts: Account[#{index + 1}/#{accounts_count}] #{account.id} - Total: #{account_time.round(2)}ms (#{account_queries} queries) | " \
          "active_plan: #{(timings[:active_plan] || 0).round(2)}ms | " \
          "features: #{(timings[:features] || 0).round(2)}ms | " \
          "role_data: #{(timings[:role_data] || 0).round(2)}ms | " \
          "plan_serializer: #{(timings[:plan_serializer] || 0).round(2)}ms | " \
          "other: #{(timings[:other] || 0).round(2)}ms"

        result
      end

      total_time = (Time.current - total_start) * 1000
      avg_per_account = accounts_count > 0 ? (query_count.to_f / accounts_count).round(2) : 0
      Rails.logger.info "[TokenValidationService] serialize_accounts: COMPLETE - #{accounts_count} accounts in #{total_time.round(2)}ms, #{query_count} total queries, #{avg_per_account} avg queries/account"

      serialized
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end
  end
end
