# frozen_string_literal: true

class Api::V1::RolesController < Api::V1::BaseController
  include RoleHelper

  before_action :check_authorization
  
  # Get available roles for account users (agent and administrator)
  # This is a global endpoint as roles are not account-specific
  def account_user_roles
    roles = Role.account_type.where(key: ['agent', 'account_owner']).map do |role|
      RoleSerializer.basic(role)
    end
    
    success_response(
      data: roles,
      message: 'Account user roles retrieved successfully'
    )
  end

  def check_authorization
    # Verificar se usuário tem permissão para gerenciar roles
    action_map = {
      'account_user_roles' => 'roles.read'
    }
    
    required_permission = action_map[action_name]
    if required_permission
      resource_key, action_key = required_permission.split('.')
      authorize_resource!(resource_key, action_key)
    else
      true # Para ações não mapeadas, permitir por enquanto
    end
  end

  def full
    load_roles
    apply_role_filters

    success_response(
      data: @roles.map { |role| RoleSerializer.full(role) },
      message: 'Roles retrieved successfully'
    )
  end

  private

  def apply_role_filters
    system_assignable_roles = @roles.where(system: true, key: ['agent', 'account_owner'])
    
    if params[:type].present?
      custom_roles = @roles.where(system: false, type: params[:type])
      @roles = system_assignable_roles.or(custom_roles)
    else
      @roles = system_assignable_roles.or(@roles.where(system: false))
    end
  end
end