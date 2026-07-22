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

    if key.blank?
      return error_response('VALIDATION_ERROR', 'Role name must contain at least one letter or number', status: :unprocessable_entity)
    end

    role = Role.new(
      key: key,
      name: role_params[:name],
      description: role_params[:description],
      system: false,
      type: 'account'
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
    if @role.system? && (role_params.key?(:key) || role_params.key?(:name))
      return error_response('FORBIDDEN', 'Cannot modify key or name of a system role', status: :forbidden)
    end

    unless @role.update(role_params)
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
    # Reconciled against the whole catalog on every boot (RbacGrantReconciler),
    # so accepting an edit here would return 200 and be reverted by the next
    # deploy. Refuse it instead of persisting a lie.
    if @role.key == RbacGrantReconciler::ROLE_KEY
      return error_response(
        'FORBIDDEN',
        'The installation owner role holds the full permission catalog by invariant ' \
        'and is reconciled on every boot; its permissions cannot be edited.',
        status: :forbidden
      )
    end

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

    unless current_api_user.has_role?('super_admin')
      caller_perms = Set.new(current_api_user.all_permissions)
      target_set   = valid_keys.to_set
      current_set  = @role.permission_keys.to_set

      granted = target_set - current_set
      revoked = current_set - target_set

      # A key that another key in the SAME target set already implies at runtime
      # carries no authority of its own: the role's users hold it either way
      # (User#has_permission? expands the implication), so writing it to the role
      # grants nothing new and dropping it takes nothing away. Neither is an
      # escalation, so neither may trip this gate.
      #
      # EVO-2127: every granular write implies `<resource>.write`, and the role
      # editor now saves the coarse key alongside the granular ones. Without this
      # exemption, an admin editing ANY pre-existing role would 403 on the first
      # save for every resource that role writes to but he does not — the coarse
      # keys are all new, so they all land in `granted`. The exemption retires
      # itself: once enforcement moves to the coarse key and the granular ones are
      # dropped, nothing implies `<resource>.write` and the gate bites again.
      implied_by_target = target_set.flat_map { |key| User::OPERATIONAL_IMPLICATIONS.fetch(key, []) }.to_set
      diffs = (granted | revoked) - implied_by_target

      unauthorized = diffs.reject { |k| caller_perms.include?(k) }
      if unauthorized.any?
        return error_response(
          'FORBIDDEN',
          "Cannot grant or revoke permissions you do not hold: #{unauthorized.join(', ')}",
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

  # Get available roles assignable to account users: the system roles
  # (agent + account_owner) plus any custom `type: 'account'` role. This is the
  # fix for "custom profile does not appear when creating an attendant" — custom
  # account roles are assignable to attendants and must be listed here.
  def account_user_roles
    roles = Role.where(type: 'account')
                .or(Role.where(key: ['agent', 'account_owner']))
                .map do |role|
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
    params.permit(:name, :description)
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
    return if current_api_user.has_role?('super_admin')
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
