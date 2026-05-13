# frozen_string_literal: true

class Api::V1::RolesController < Api::V1::BaseController
  include RoleHelper

  before_action :check_authorization
  before_action :load_role, only: [:show, :update, :destroy, :bulk_update_permissions]
  before_action :enforce_role_scope!, only: [:show, :update, :destroy, :bulk_update_permissions]

  def index
    @roles = scoped_roles.includes(:role_permissions_actions, :users)
    success_response(
      data: @roles.map { |role| role_serializer(role) },
      message: 'Roles retrieved successfully'
    )
  end

  def show
    success_response(
      data: role_serializer(@role),
      message: 'Role retrieved successfully'
    )
  end

  def create
    key = role_params[:name].to_s.downcase.gsub(/\s+/, '_').gsub(/[^a-z0-9_]/, '')
    role = Role.new(
      key: key,
      name: role_params[:name],
      description: role_params[:description],
      system: false,
      type: account_owner_only? ? 'account' : (role_params[:type].presence || 'account')
    )

    unless role.save
      return render_unprocessable_entity(role.errors)
    end

    success_response(
      data: role_serializer(role),
      message: 'Role created successfully',
      status: :created
    )
  end

  def update
    if @role.system? && role_params.key?(:key)
      return error_response('FORBIDDEN', 'Cannot modify key of a system role', status: :forbidden)
    end

    unless @role.update(role_params.except(:key, :type))
      return render_unprocessable_entity(@role.errors)
    end

    success_response(
      data: role_serializer(@role),
      message: 'Role updated successfully'
    )
  end

  def destroy
    unless @role.can_be_deleted?
      message = @role.system? ? 'Cannot delete system roles' : 'Cannot delete role with assigned users'
      return error_response('FORBIDDEN', message, status: :forbidden)
    end

    @role.destroy!
    success_response(data: nil, message: 'Role deleted successfully')
  end

  def bulk_update_permissions
    permission_keys = params[:permission_keys]

    unless permission_keys.is_a?(Array)
      return error_response('VALIDATION_ERROR', 'permission_keys must be an array', status: :bad_request)
    end

    valid_keys = permission_keys.select { |k| ResourceActionsConfig.valid_permission?(k) }
    invalid_keys = permission_keys - valid_keys

    if invalid_keys.any?
      return error_response(
        'VALIDATION_ERROR',
        "Invalid permission keys: #{invalid_keys.join(', ')}",
        status: :unprocessable_entity
      )
    end

    if account_owner_only?
      caller_permissions = Set.new(current_api_user.all_permissions)
      unauthorized_keys = valid_keys.reject { |k| caller_permissions.include?(k) }
      if unauthorized_keys.any?
        return error_response(
          'FORBIDDEN',
          "Cannot grant permissions you do not hold: #{unauthorized_keys.join(', ')}",
          status: :forbidden
        )
      end
    end

    ActiveRecord::Base.transaction do
      @role.role_permissions_actions.destroy_all
      valid_keys.each { |key| @role.role_permissions_actions.create!(permission_key: key) }
    end

    success_response(
      data: role_serializer(@role.reload),
      message: 'Permissions updated successfully'
    )
  end

  # Get available roles for account users (agent and account_owner)
  def account_user_roles
    roles = Role.account_type.where(key: ['agent', 'account_owner']).map do |role|
      RoleSerializer.basic(role)
    end

    success_response(
      data: roles,
      message: 'Account user roles retrieved successfully'
    )
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

  def role_params
    params.permit(:name, :description, :key, :type)
  end

  def load_role
    @role = Role.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_not_found('Role not found')
  end

  def scoped_roles
    account_owner_only? ? Role.where(type: 'account') : Role.all
  end

  def account_owner_only?
    current_api_user.has_role?('account_owner') && !current_api_user.has_role?('super_admin')
  end

  def enforce_role_scope!
    return unless @role
    return unless account_owner_only?
    return if @role.type == 'account'

    error_response('FORBIDDEN', 'Cannot access or modify user-type roles', status: :forbidden)
  end

  def check_authorization
    action_map = {
      'index'                   => 'roles.read',
      'show'                    => 'roles.read',
      'account_user_roles'      => 'roles.read',
      'full'                    => 'roles.read',
      'create'                  => 'roles.create',
      'update'                  => 'roles.update',
      'destroy'                 => 'roles.delete',
      'bulk_update_permissions' => 'roles.bulk_update_permissions'
    }

    required_permission = action_map[action_name]
    if required_permission
      resource_key, action_key = required_permission.split('.')
      authorize_resource!(resource_key, action_key)
    else
      true
    end
  end

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
