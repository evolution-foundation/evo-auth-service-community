class Api::V1::UsersController < Api::BaseController
  AUTHZ_CACHE_TTL = 60.seconds

  before_action :fetch_user, except: [:create, :index, :bulk_create]
  before_action :check_authorization

  def index
    @users = Users::FilterService.new(params[:filters], params[:q]).resolve

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
      # The form sends the user's chosen password and the controller permits it
      # in `new_user_params`. Forward it so AgentBuilder uses it instead of
      # silently generating a random one — otherwise the user is created with
      # a password they don't know and login always returns 401.
      password: new_user_params['password'],
      role: new_user_params['role'].presence || 'agent',
      availability: new_user_params['availability'],
      inviter: current_user
    )

    @user = builder.perform
    success_response(
      data: { user: UserSerializer.full(@user) },
      message: 'User created successfully',
      status: :created
    )
  rescue ActiveRecord::RecordInvalid => e
    error_response(
      ApiErrorCodes::VALIDATION_ERROR,
      'Validation failed',
      details: format_validation_errors(e.record.errors),
      status: :unprocessable_entity
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
        role: (params[:role] || :agent).to_sym,
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
    # IMPORTANT: read actions stay gated on `users.read` (OPERATIONAL), not
    # `users.manage` (ADMINISTRATIVE). The Conversations screen needs to load
    # the attendant list/filters via GET /api/v1/users, so any role with
    # conversations.read receives users.read operationally (see User model's
    # OPERATIONAL_IMPLICATIONS). Gating these endpoints on users.manage would
    # 403 the attendant dropdown in Conversations — rejected by design.
    # The administrative gate (Settings > Agents) is keyed on users.manage and
    # IS enforced here, on top of the fine keys — see administrative_action?.
    # The frontend gate remains, but is no longer the only one.
    action_map = {
      'index' => 'users.read',
      'show' => 'users.read',
      'create' => 'users.create',
      'update' => 'users.update',
      'destroy' => 'users.delete',
      'bulk_create' => 'users.bulk_operations',
      'permissions' => 'users.read',
      'check_permission' => 'users.read',
      'role' => 'users.read'
    }

    required_permission = action_map[action_name]
    if required_permission
      authorize_resource!('users', required_permission.split('.').last)
      # authorize_resource! renders on deny (truthy return) — performed? is the
      # halt signal; a second authorize after a render would DoubleRenderError.
      return false if performed?
      # Administrative user management (creating/deleting agents, batch
      # imports, role assignment) additionally requires users.manage — the
      # endpoint-level mirror of the frontend Settings > Agents gate. Reads and
      # self-service updates (no role CHANGE) stay on the fine keys alone.
      return authorize_resource!('users', 'manage') if administrative_action?

      return true
    end

    # Fail closed: an action with no explicit permission mapping must never be
    # implicitly authorized when it can mutate state. Read-only verbs (GET/HEAD)
    # carry no mutation risk and stay permissive so self/read endpoints keep
    # working; any other verb is denied unless it arrives through an already
    # authorized service or exempt channel (parity with authorize_resource!).
    return true if request.get? || request.head?
    return true if exempt_from_permission_check?
    return true if Current.service_authenticated == true

    respond_forbidden("You don't have permission to perform this action")
  end

  # Mutations that manage OTHER users (the Settings > Agents surface): create,
  # destroy, batch import, and any update that CHANGES the role set. The
  # community frontend sends `role` on every user update, so an update that
  # leaves the role set untouched must not trip the administrative gate (a
  # users.update-only caller renaming a user would 403 otherwise).
  def administrative_action?
    return true if %w[create destroy bulk_create].include?(action_name)
    return false unless action_name == 'update' && params[:role].present?

    role_set_change?
  end

  # The question is not "is the submitted key one the target already holds?" but
  # "will update_user_role change what the target holds?" — it destroys EVERY
  # non-system role before assigning, so resubmitting a role the target already
  # has still REVOKES any other non-system role. Both are role management.
  def role_set_change?
    target = @user || User.find_by(id: params[:id])
    return true unless target&.has_role?(params[:role])

    target.user_roles.joins(:role)
          .where(roles: { system: false })
          .where.not(roles: { key: params[:role] })
          .exists?
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
