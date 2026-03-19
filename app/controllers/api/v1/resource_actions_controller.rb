# frozen_string_literal: true

class Api::V1::ResourceActionsController < Api::V1::BaseController
  before_action :check_authorization, except: [:index]
  
  # Public endpoint to get all available resources and actions
  # This provides the frontend with the authoritative list of permissions
  def index
    success_response(
      data: ResourceActionsConfig.api_format,
      meta: {
        total_resources: ResourceActionsConfig.all_resources.size,
        total_permissions: ResourceActionsConfig.all_permission_keys.size,
        last_updated: Time.current.iso8601
      },
      message: 'Resource actions configuration retrieved successfully'
    )
  end

  # Get configuration for a specific resource
  def show
    resource_key = params[:id]
    resource_config = ResourceActionsConfig.resource(resource_key)

    if resource_config
      success_response(
        data: {
          key: resource_key,
          name: resource_config[:name],
          description: resource_config[:description],
          actions: resource_config[:actions].transform_values do |action_config|
            {
              name: action_config[:name],
              description: action_config[:description]
            }
          end,
          permissions: ResourceActionsConfig.resource_actions(resource_key).keys.map do |action_key|
            permission_key = ResourceActionsConfig.permission_key(resource_key, action_key)
            {
              key: permission_key,
              display_name: ResourceActionsConfig.permission_display_name(permission_key),
              action: action_key,
              action_name: ResourceActionsConfig.action(resource_key, action_key)[:name]
            }
          end
        },
        message: 'Resource configuration retrieved successfully'
      )
    else
      error_response('NOT_FOUND', 'Resource not found', status: :not_found)
    end
  end

  # Validate a permission key
  def validate
    permission_key = params[:permission_key]
    
    if permission_key.blank?
      return error_response('VALIDATION_ERROR', 'Permission key is required', status: :bad_request)
    end

    is_valid = ResourceActionsConfig.valid_permission?(permission_key)
    
    response_data = {
      permission_key: permission_key,
      valid: is_valid
    }

    if is_valid
      resource_key, action_key = permission_key.split('.')
      response_data.merge!(
        display_name: ResourceActionsConfig.permission_display_name(permission_key),
        resource: resource_key,
        action: action_key,
        resource_name: ResourceActionsConfig.resource(resource_key)[:name],
        action_name: ResourceActionsConfig.action(resource_key, action_key)[:name],
        description: ResourceActionsConfig.action(resource_key, action_key)[:description]
      )
    end

    success_response(
      data: response_data,
      message: is_valid ? 'Permission key validated successfully' : 'Permission key is invalid'
    )
  end

  private

  def check_authorization
    # Verificar se usuário tem permissão para gerenciar configurações de recursos
    action_map = {
      'index' => 'resource_actions.read',
      'show' => 'resource_actions.read',
      'validate' => 'resource_actions.validate'
    }
    
    required_permission = action_map[action_name]
    if required_permission
      resource_key, action_key = required_permission.split('.')
      authorize_resource!(resource_key, action_key)
    else
      true # Para ações não mapeadas, permitir por enquanto
    end
  end
end