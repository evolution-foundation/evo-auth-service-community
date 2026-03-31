# frozen_string_literal: true

# Controller concern for permission checking
module PermissionCheckable
  extend ActiveSupport::Concern
  include AuthenticationRoutesExemption
  
  included do
    # Define helper_method se estivermos em um controller que suporta isso (ActionController)
    helper_method :current_permission_service if respond_to?(:helper_method)
    rescue_from AuthorizationError, with: :handle_authorization_error
  end
  
  # Checks if the user has permission to access a specific resource and action
  # Raises an authorization error if the user does not have permission or redirects in HTML
  #
  # @param resource [String] The resource to check
  # @param action [String] The action to check
  # @param message [String] (Optional) Custom error message
  def authorize_resource!(resource, action, message = nil)
    # Verifica se a rota está isenta de verificação de permissão
    return true if exempt_from_permission_check?
    return true if Current.service_authenticated == true

    # Verifica se usuário está autenticado
    unless current_api_user
      error_message = "Authentication required for this operation"
      respond_unauthorized(error_message)
      return false
    end

    permission_key = "#{resource}.#{action}"

    has_permission = if current_api_user.respond_to?(:has_permission?)
                       current_api_user.has_permission?(permission_key)
                     else
                       current_permission_service.can?(resource, action)
                     end

    Rails.logger.info "Permission check for #{permission_key}: user_id=#{current_api_user.id}, has_permission=#{has_permission}"
    return true if has_permission

    error_message = message || "You don't have permission to #{action} on #{resource}"
    Rails.logger.warn "Permission denied: #{error_message} (user_id: #{current_api_user.id}, permission: #{permission_key})"
    respond_forbidden(error_message)
  end
  
  # Helper method to respond with unauthorized status
  def respond_unauthorized(error_message)
    render json: { error: error_message }, status: :unauthorized
  end
  
  # Helper method to respond with forbidden status
  def respond_forbidden(error_message)
    render json: { error: error_message }, status: :forbidden
  end
  
  # Checks if the user has a specific role
  # Compatibility with previous code
  def authorize_role!(role_key, message = nil)
    # Verifica se a rota está isenta de verificação de permissão
    return true if exempt_from_permission_check?
    return true if Current.service_authenticated == true
    
    # Verifica se usuário está autenticado
    unless current_api_user
      error_message = "Authentication required for this operation"
      respond_unauthorized(error_message)
      return false
    end
    
    has_role = if current_api_user.respond_to?(:roles)
                 current_api_user.roles.where(key: role_key).exists?
               else
                 current_permission_service.has_role?(role_key)
               end
    
    return true if has_role
    
    error_message = message || "You don't have permission to access this area"
    respond_forbidden(error_message)
    
    false
  end
  
  # Permission service for the current user (compatibility with legacy code)
  def current_permission_service
    @current_permission_service ||= if defined?(UserPermissionService)
                                     UserPermissionService.new(current_api_user || current_user)
                                   else
                                     NullPermissionService.new
                                   end
  end
  
  # Authorization error handling
  def handle_authorization_error(exception)
    render json: { error: exception.message }, status: :forbidden
  end
  
  # Authorization error class
  class AuthorizationError < StandardError
    def initialize(message = "Unauthorized access")
      super(message)
    end
  end
  
  # Null service for cases where no permission service is defined
  class NullPermissionService
    def can?(*)
      false
    end
    
    def has_role?(*)
      false
    end
  end
end
