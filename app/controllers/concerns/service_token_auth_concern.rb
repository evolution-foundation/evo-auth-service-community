module ServiceTokenAuthConcern
  extend ActiveSupport::Concern

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
    ENV['EVOAI_AUTH_API_TOKEN'].presence || ENV['EVOAI_CRM_API_TOKEN'].presence
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
