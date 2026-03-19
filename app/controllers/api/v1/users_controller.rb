class Api::V1::UsersController < Api::V1::BaseController
  include AuthHelper
  AUTHZ_CACHE_TTL = 60.seconds
  
  before_action :set_current_account_context
  before_action :check_authorization
  before_action :set_user, only: [:show, :update, :destroy, :update_password, :update_mfa]

  def index
    @users = Current.account.users.includes(:account_users, :user_roles, :roles).order_by_full_name

    log_user_list_access

    apply_pagination

    paginated_response(
      data: @users.map { |user| UserSerializer.list(user) },
      collection: @users,
      message: 'Users retrieved successfully'
    )
  end

  def show
    success_response(
      data: UserSerializer.full(@user),
      message: 'User retrieved successfully'
    )
  end

  def create
    if Current.account.present?
      builder = AgentBuilder.new(
        email: params[:email],
        name: params[:name],
        role: params[:role] || 'agent',
        availability: params[:availability] || 'online',
        auto_offline: params[:auto_offline] || false,
        password: params[:password],
        inviter: current_user,
        account: Current.account
      )

      user = builder.perform
      return success_response(
        data: UserSerializer.user_with_account_data(user, Current.account),
        message: 'User created successfully',
        status: :created
      )
    end

    create_user
  end

  def update
    if @user.update(user_params)
      success_response(
        data: UserSerializer.full(@user),
        message: 'User updated successfully'
      )
    else
      render_unprocessable_entity(@user.errors)
    end
  end

  def destroy
    @user.destroy
    success_response(data: {}, message: 'User deleted successfully')
  end

  def update_password
    if @user.valid_password?(params[:current_password])
      if @user.update(password: params[:new_password])
        success_response(data: {}, message: 'Password updated successfully')
      else
        render_unprocessable_entity(@user.errors)
      end
    else
      error_response('VALIDATION_ERROR', 'Current password is incorrect', status: :unprocessable_entity)
    end
  end

  def update_mfa
    if @user.update(mfa_params)
      success_response(
        data: UserSerializer.full(@user),
        message: 'MFA settings updated successfully'
      )
    else
      render_unprocessable_entity(@user.errors)
    end
  end

  def permissions
      if Current.account.present?
        account_user = current_user.account_users.find_by(account: Current.account)
        return error_response('FORBIDDEN', 'You do not have access to this account', status: :forbidden) unless account_user

        return success_response(
          data: {
            permissions: account_user.permissions,
            role_data: account_user.role_data
          },
          message: 'Account permissions retrieved successfully'
        )
      end

      # Fallback: permissões globais do usuário (baseadas em user_roles)
      permissions = current_user.permissions
      success_response(
        data: {
          permissions: permissions,
          role_data: current_user.role_data
        },
        message: 'User permissions retrieved successfully'
      )
  end

  def check_permission
    # Apenas POST suportado
    permission_key = params[:permission_key] || request_body['permission_key']
    
    return error_response('VALIDATION_ERROR', 'Permission key is required', status: :bad_request) if permission_key.blank?

    has_permission = Rails.cache.fetch(
      user_permission_cache_key(current_user.id, permission_key, Current.account&.id),
      expires_in: AUTHZ_CACHE_TTL
    ) do
      if Current.account.present?
        account_user = current_user.account_users.find_by(account: Current.account)
        account_user&.has_permission?(permission_key) || false
      else
        current_user.check_permission(permission_key)
      end
    end

    success_response(
      data: {
        permission_key: permission_key,
        has_permission: has_permission,
      },
      message: has_permission ? 'Permission granted' : 'Permission denied'
    )
  end

  private

  def request_body
    @request_body ||= JSON.parse(request.body.read) rescue {}
  end

  def set_user
    @user = Current.account.users.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_not_found('User not found')
  end

  def user_params
    permitted_params = params.require(:user).permit(:name, :email, :password, :password_confirmation, :display_name, :availability, :role)
    permitted_params
  end

  def mfa_params
    params.require(:user).permit(:mfa_method, :otp_required_for_login)
  end

  def user_permission_cache_key(user_id, permission_key, account_id = nil)
    "authz:user_permission:user=#{user_id}:account=#{account_id || 'none'}:permission=#{permission_key}"
  end

  def log_user_list_access
    Rails.logger.info(
      "[AUDIT] User list accessed | user_id=#{current_user.id} " \
      "ip=#{request.remote_ip} account_id=#{Current.account&.id || 'global'} " \
      "page=#{params[:page] || 1} page_size=#{params[:pageSize] || params[:page_size] || 20}"
    )
  end

  def set_current_account_context
    account = Account.first
    Current.account = account if account
  end

  def check_authorization
    # Verificar se usuário tem permissão para gerenciar users
    action_map = {
      'index' => 'users.read',
      'show' => 'users.read',
      'create' => 'users.create',
      'update' => 'users.update',
      'destroy' => 'users.delete',
      'update_password' => 'users.change_password',
      'update_mfa' => 'users.manage_mfa',
      'permissions' => 'users.read',
      'check_permission' => 'users.read'
    }
    
    required_permission = action_map[action_name]
    if required_permission
      resource_key, action_key = required_permission.split('.')
      authorize_resource!(resource_key, action_key)
    else
      true
    end
  end
end
