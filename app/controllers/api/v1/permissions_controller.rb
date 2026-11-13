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
    
    cache_context = if @access_token.present?
                      # Keyed by token and scope set: two tokens of one user, or one token
                      # before and after a scope change, get their own verdicts.
                      "api_access_token:#{@access_token.id}:#{Digest::SHA256.hexdigest(@access_token.scopes.to_s)}"
                    elsif @doorkeeper_token.present?
                      'bearer'
                    else
                      'unknown'
                    end
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

  # An API token grants what its scopes allow AND its owner holds.
  def check_access_token_permission(permission_key)
    @access_token.has_scope?(permission_key) && current_user.has_permission?(permission_key)
  end

  def cache_key_for_permission(user_id, permission_key, auth_type)
    "authz:permissions_check:user=#{user_id}:auth=#{auth_type}:permission=#{permission_key}"
  end
end
