module ServiceTokenAuthConcern
  extend ActiveSupport::Concern

  # No fallback to EVOAI_CRM_API_TOKEN: that is the CRM's own credential, and
  # inheriting it made a shared quickstart default the auth's service token,
  # which bypasses every authorize_* gate (CRM-829).
  # Published in the quickstart's .env.example: every default install shared it.
  PUBLIC_DEFAULT_TOKENS = %w[6e10e689-58ce-4416-bf0d-f5818bf2dcf8].freeze

  def self.expected_service_token
    ENV['EVOAI_AUTH_API_TOKEN'].presence
  end

  def self.verify_configured!
    token = expected_service_token
    raise 'EVOAI_AUTH_API_TOKEN must be set (generate one with `openssl rand -hex 32`)' if token.blank?
    return unless PUBLIC_DEFAULT_TOKENS.include?(token.strip)

    raise 'EVOAI_AUTH_API_TOKEN is the public quickstart default; generate a new one with `openssl rand -hex 32`'
  end

  private

  def service_token_from_header
    request.headers['X-Service-Token'] ||
      request.headers['HTTP_X_SERVICE_TOKEN'] ||
      request.headers['X-Internal-API-Token'] ||
      request.headers['HTTP_X_INTERNAL_API_TOKEN']
  end

  def service_token_present?
    service_token_from_header.present?
  end

  def expected_service_token
    ServiceTokenAuthConcern.expected_service_token
  end

  def valid_service_token?
    expected_token = expected_service_token
    provided_token = service_token_from_header

    return false if expected_token.blank? || provided_token.blank?

    ActiveSupport::SecurityUtils.secure_compare(expected_token, provided_token)
  end

  def authenticate_service_token!
    return false unless service_token_present?

    unless valid_service_token?
      render_service_token_unauthorized('Invalid service token')
      return false
    end

    set_service_authenticated_context
    true
  end

  def set_service_authenticated_context
    Current.service_authenticated = true
    Current.authentication_method = 'service_token'
  end

  def render_service_token_unauthorized(message = 'Unauthorized')
    render json: {
      error: message,
      code: 'SERVICE_TOKEN_UNAUTHORIZED',
      timestamp: Time.current.iso8601
    }, status: :unauthorized
  end

  def service_authenticated?
    Current.service_authenticated == true
  end
end
