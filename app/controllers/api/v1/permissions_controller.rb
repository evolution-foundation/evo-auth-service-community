class Api::V1::PermissionsController < Api::BaseController
  AUTHZ_CACHE_TTL = 60.seconds

  def index
    success_response(
      data: {
        permissions: current_user.permissions,
        role_data: current_user.role_data
      },
      message: 'User permissions retrieved successfully'
    )
  end

  def check
    permission_key = params[:permission_key]
    
    return error_response('VALIDATION_ERROR', 'Permission key is required', status: :bad_request) if permission_key.blank?
    
    cache_context = @access_token.present? ? 'api_access_token' : (@doorkeeper_token.present? ? 'bearer' : 'unknown')
    has_permission = false

    # Verificar tipo de autenticação e processar adequadamente
    if @access_token.present?
      # Fluxo com api_access_token
      has_permission = Rails.cache.fetch(
        cache_key_for_permission(current_user.id, permission_key, cache_context),
        expires_in: AUTHZ_CACHE_TTL
      ) do
        check_access_token_permission(permission_key)
      end
    elsif @doorkeeper_token.present?
      # Fluxo com bearer token
      has_permission = Rails.cache.fetch(
        cache_key_for_permission(current_user.id, permission_key, cache_context),
        expires_in: AUTHZ_CACHE_TTL
      ) do
        @current_user.check_permission(permission_key)
      end
    else
      return error_response('VALIDATION_ERROR', 'Invalid authentication method', status: :unauthorized)
    end

    success_response(
      data: {
        has_permission: has_permission,
        permission_key: permission_key
      },
      message: has_permission ? 'Permission granted' : 'Permission denied'
    )
  end

  private

  def check_access_token_permission(permission_key)
    # Para api_access_token, verificar primeiro se o token tem o scope necessário
    unless @access_token.has_scope?(permission_key)
      return false
    end

    true
  end

  def cache_key_for_permission(user_id, permission_key, auth_type)
    "authz:permissions_check:user=#{user_id}:auth=#{auth_type}:permission=#{permission_key}"
  end
end
