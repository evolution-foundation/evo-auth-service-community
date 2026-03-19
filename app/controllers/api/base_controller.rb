class Api::BaseController < ApplicationController
  include Pundit::Authorization
  include PermissionCheckable
  include ApiResponseHelper
  include ServiceTokenAuthConcern

  respond_to :json

  before_action :authenticate_request!
  before_action :set_current_user

  rescue_from TokenValidationService::InvalidToken, with: :render_invalid_token
  rescue_from TokenValidationService::ExpiredToken, with: :render_expired_token
  rescue_from TokenValidationService::TokenNotFound, with: :render_token_not_found
  
  # Global exception handlers for standardized error responses
  rescue_from ActiveRecord::RecordNotFound, with: :handle_record_not_found
  rescue_from ActiveRecord::RecordInvalid, with: :handle_record_invalid
  rescue_from ActiveRecord::RecordNotUnique, with: :handle_record_not_unique
  rescue_from Pundit::NotAuthorizedError, with: :handle_not_authorized
  rescue_from ActionController::ParameterMissing, with: :handle_parameter_missing
  rescue_from StandardError, with: :handle_internal_error
  
  private

  def authenticate_request!
    return true if exempt_from_permission_check?
    # Keep regular auth flow as priority to avoid impacting user login/session behavior.
    if request.headers['Authorization'].present? || request.headers['api_access_token'].present? || request.headers['HTTP_API_ACCESS_TOKEN'].present?
      @token_validator = TokenValidationService.new(request)
      result = @token_validator.validate!

      # Minimize overhead by using token reference when available.
      user_id = if @token_validator.token_type == :bearer
        @token_validator.token&.resource_owner_id || result.dig(:user, :id)
      else
        result.dig(:user, :id)
      end

      @current_user = User.find(user_id)
      @validation_result = result

      # Reuse the token already loaded during validation (avoids extra DB query)
      set_token_references_from_validator
      return
    end

    if service_token_present?
      authenticate_service_token!
      return if performed? || Current.service_authenticated == true
    end

    render_token_not_found('Authentication required')
  end

  def set_token_references_from_validator
    loaded_token = @token_validator.token
    return unless loaded_token

    case @token_validator.token_type
    when :bearer
      @doorkeeper_token = loaded_token
    when :api_access_token
      @access_token = loaded_token
    end
  end

  def set_current_user
    Current.user = @current_user if @current_user
  end

  def current_user
    @current_user
  end

  def current_api_user
    @current_user
  end

  # Handle ActiveRecord::RecordNotFound
  def handle_record_not_found(exception)
    resource_name = exception.model.to_s.underscore.upcase
    error_code = "#{resource_name}_NOT_FOUND"
    
    # Use predefined error code if exists, fallback to dynamic
    error_code = ApiErrorCodes.const_get(error_code) if ApiErrorCodes.const_defined?(error_code)
    
    error_response(
      error_code,
      "#{exception.model} not found",
      details: { id: exception.id, model: exception.model },
      status: :not_found
    )
  end

  # Handle ActiveRecord::RecordInvalid (validation errors)
  def handle_record_invalid(exception)
    error_response(
      ApiErrorCodes::VALIDATION_ERROR,
      'Validation failed',
      details: format_validation_errors(exception.record.errors),
      status: :unprocessable_entity
    )
  end

  # Handle ActiveRecord::RecordNotUnique (duplicate entries)
  def handle_record_not_unique(exception)
    error_response(
      ApiErrorCodes::RESOURCE_ALREADY_EXISTS,
      'Resource already exists',
      details: { message: exception.message },
      status: :conflict
    )
  end

  # Handle Pundit::NotAuthorizedError (authorization failures)
  def handle_not_authorized(exception)
    error_response(
      ApiErrorCodes::FORBIDDEN,
      'You are not authorized to perform this action',
      details: { 
        action: exception.query,
        record: exception.record.class.name
      },
      status: :forbidden
    )
  end

  # Handle ActionController::ParameterMissing
  def handle_parameter_missing(exception)
    error_response(
      ApiErrorCodes::MISSING_REQUIRED_FIELD,
      "Required parameter missing: #{exception.param}",
      details: { parameter: exception.param },
      status: :bad_request
    )
  end

  # Handle generic StandardError (catch-all for unexpected errors)
  def handle_internal_error(exception)
    return if performed?

    # Log the full error for debugging
    Rails.logger.error "Internal Server Error: #{exception.class} - #{exception.message}"
    Rails.logger.error exception.backtrace.join("\n")

    # In production, don't expose internal error details
    if Rails.env.production?
      error_response(
        ApiErrorCodes::INTERNAL_ERROR,
        'An unexpected error occurred',
        status: :internal_server_error
      )
    else
      # In development, include more details for debugging
      error_response(
        ApiErrorCodes::INTERNAL_ERROR,
        exception.message,
        details: {
          exception_class: exception.class.name,
          backtrace: exception.backtrace.first(5)
        },
        status: :internal_server_error
      )
    end
  end

  # Format validation errors into structured array
  def format_validation_errors(errors)
    errors.messages.map do |field, messages|
      {
        field: field,
        messages: messages,
        full_messages: errors.full_messages_for(field)
      }
    end
  end

  MAX_PAGE_SIZE = 100

  def apply_pagination
    # Padrão: page e pageSize (camelCase) conforme API_RESPONSE_STANDARD.md
    # Aceita pageSize (padrão) ou page_size/per_page (compatibilidade)
    page = params[:page]&.to_i || 1
    page_size = params[:pageSize]&.to_i || params[:page_size]&.to_i || params[:per_page]&.to_i || 20
    page_size = [[page_size.to_i, 1].max, MAX_PAGE_SIZE].min

    # Chama paginate_instance_variables se existir, senão aplica paginação diretamente nas variáveis de instância
    if respond_to?(:paginate_instance_variables, true)
      paginate_instance_variables(page, page_size)
    else
      # Implementação padrão para controllers que não têm paginate_instance_variables
      instance_variables.each do |var_name|
        var = instance_variable_get(var_name)
        next unless var.respond_to?(:page)

        instance_variable_set(var_name, var.page(page).per(page_size))
      end
    end
  end

  # Standardized helper methods for common error responses

  def render_unprocessable_entity(errors)
    error_response(
      ApiErrorCodes::VALIDATION_ERROR,
      'Validation failed',
      details: format_validation_errors(errors),
      status: :unprocessable_entity
    )
  end

  def render_not_found(message = 'Resource not found')
    error_response(
      ApiErrorCodes::RESOURCE_NOT_FOUND,
      message,
      status: :not_found
    )
  end

  def render_invalid_token(message = 'Invalid token')
    error_response(
      'INVALID_TOKEN',
      message,
      status: :unauthorized
    )
  end

  def render_expired_token(message = 'Token expired')
    error_response(
      'EXPIRED_TOKEN',
      message,
      status: :unauthorized
    )
  end

  def render_token_not_found(message = 'Token not found')
    error_response(
      'TOKEN_NOT_FOUND',
      message,
      status: :unauthorized
    )
  end
end
