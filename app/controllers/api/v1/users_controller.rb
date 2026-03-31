class Api::V1::UsersController < Api::BaseController
  AUTHZ_CACHE_TTL = 60.seconds

  before_action :fetch_user, except: [:create, :index, :bulk_create]
  before_action :check_authorization

  def index
    @users = users

    apply_pagination

    paginated_response(
      data: @users.map { |user| UserSerializer.full(user) },
      collection: @users,
      message: 'Users retrieved successfully'
    )
  end

  def create
    builder = AgentBuilder.new(
      email: new_user_params['email'],
      name: new_user_params['name'],
      role: new_user_params['role'],
      availability: new_user_params['availability'],
      inviter: current_user
    )

    @user = builder.perform
    success_response(
      data: { user: UserSerializer.full(@user) },
      message: 'User created successfully',
      status: :created
    )
  end

  def update
    ActiveRecord::Base.transaction do
      @user.update!(user_params.slice(:name, :availability).compact)

      if user_params[:role].present?
        update_user_role(user_params[:role])
      end
    end

    success_response(
      data: { user: UserSerializer.full(@user) },
      message: 'User updated successfully'
    )
  rescue StandardError => e
    Rails.logger.error "❌ Error updating user: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    error_response('VALIDATION_ERROR', e.message, status: :unprocessable_entity)
  end

  def destroy
    if @user.id == current_user.id
      return error_response('SELF_DELETION', 'You cannot delete your own account', status: :unprocessable_entity)
    end

    @user.destroy!
    success_response(
      data: { id: @user.id },
      message: 'User deleted successfully'
    )
  end

  def bulk_create
    emails = params[:emails]

    emails.each do |email|
      builder = AgentBuilder.new(
        email: email,
        name: email.split('@').first,
        inviter: current_user
      )
      begin
        builder.perform
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.info "[User#bulk_create] ignoring email #{email}, errors: #{e.record.errors}"
      end
    end

    success_response(
      data: { count: emails.count },
      message: 'Users bulk created successfully'
    )
  end

  def check_permission
    permission_key = params[:permission_key]

    return error_response('VALIDATION_ERROR', 'Permission key is required', status: :bad_request) if permission_key.blank?

    target_user = @user || current_user

    has_permission = Rails.cache.fetch(
      permission_cache_key(target_user.id, permission_key),
      expires_in: AUTHZ_CACHE_TTL
    ) do
      target_user.has_permission?(permission_key)
    end

    success_response(data: {
      permission_key: permission_key,
      has_permission: has_permission,
      role: target_user.role_data
    }, message: has_permission ? 'Permission granted' : 'Permission denied')
  end

  def role
    target_user = @user || current_user

    role_data = Rails.cache.fetch(
      role_cache_key(target_user.id),
      expires_in: AUTHZ_CACHE_TTL
    ) do
      target_user.role_data
    end

    success_response(
      data: { role: role_data },
      message: 'User role retrieved successfully'
    )
  end

  private

  def update_user_role(role_key)
    system_role = Role.find_by(key: role_key)
    raise ActiveRecord::RecordNotFound, "Role '#{role_key}' not found" unless system_role

    existing = @user.user_roles.joins(:role).where(roles: { system: false })
    existing.destroy_all if existing.exists?

    UserRole.assign_role_to_user(@user, system_role, current_user)
  end

  def check_authorization
    action_map = {
      'index' => 'users.read',
      'show' => 'users.read',
      'create' => 'users.create',
      'update' => 'users.update',
      'destroy' => 'users.delete',
      'bulk_create' => 'users.bulk_operations',
      'permissions' => 'users.read',
      'check_permission' => 'users.read'
    }

    required_permission = action_map[action_name]
    if required_permission
      authorize_resource!('users', required_permission.split('.').last)
    else
      true
    end
  end

  def fetch_user
    @user = users.find(params[:id])
  end

  def allowed_user_params
    [:name, :email, :role, :availability, :password]
  end

  def user_params
    params.permit(allowed_user_params)
  end

  def new_user_params
    params.permit(:email, :name, :role, :availability, :password)
  end

  def users
    @users ||= User.order_by_full_name.includes(:user_roles)
  end

  def permission_cache_key(user_id, permission_key)
    "authz:permission:user=#{user_id}:permission=#{permission_key}"
  end

  def role_cache_key(user_id)
    "authz:role:user=#{user_id}"
  end
end
