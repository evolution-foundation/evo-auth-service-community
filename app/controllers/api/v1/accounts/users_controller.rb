class Api::V1::Accounts::UsersController < Api::V1::Accounts::BaseController
  AUTHZ_CACHE_TTL = 60.seconds

  before_action :fetch_user, except: [:create, :index, :bulk_create]
  before_action :check_authorization
  before_action :validate_limit, only: [:create]
  before_action :validate_limit_for_bulk_create, only: [:bulk_create]

  def index
    @users = users
    
    apply_pagination
    
    paginated_response(
      data: @users.map { 
        |user| UserSerializer.user_with_account_data(user, Current.account) 
      },
      collection: @users,
      message: 'Account users retrieved successfully'
    )
  end

  def create
    builder = AgentBuilder.new(
      email: new_user_params['email'],
      name: new_user_params['name'],
      role: new_user_params['role'],
      availability: new_user_params['availability'],
      auto_offline: new_user_params['auto_offline'],
      inviter: current_user,
      account: Current.account
    )

    @user = builder.perform
    success_response(
      data: { user: UserSerializer.user_with_account_data(@user, Current.account) },
      message: 'User created successfully',
      status: :created
    )
  end

  def update
    ActiveRecord::Base.transaction do
      # Atualizar dados básicos do usuário
      @user.update!(user_params.slice(:name).compact)
      
      # Buscar o account_user para esta conta
      account_user = @user.account_users.find_by(account: Current.account)
      return error_response('NOT_FOUND', 'User not found in this account', status: :not_found) unless account_user
      
      # Atualizar dados do account_user (exceto role que é tratado separadamente)
      account_user_data = user_params.slice(*account_user_attributes).compact
      
      account_user.update!(account_user_data)
      
      # Processar mudança de role se fornecida
      if user_params[:role].present?
        update_user_role(user_params[:role], account_user)
      end
    end
    
    success_response(
      data: { user: UserSerializer.user_with_account_data(@user, Current.account) },
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

    account_user = @user.account_users.find_by(account: Current.account)
    return error_response('NOT_FOUND', 'User not found in this account', status: :not_found) unless account_user
    
    account_user.destroy!
    delete_user_record(@user)
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
        inviter: current_user,
        account: Current.account
      )
      begin
        builder.perform
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.info "[User#bulk_create] ignoring email #{email}, errors: #{e.record.errors}"
      end
    end

    # This endpoint is used to bulk create users during onboarding
    # onboarding_step key in present in Current account custom attributes, since this is a one time operation
    Current.account.custom_attributes.delete('onboarding_step')
    Current.account.save!
    success_response(
      data: { count: emails.count },
      message: 'Users bulk created successfully'
    )
  end

  def check_permission
    permission_key = params[:permission_key]
    
    return error_response('VALIDATION_ERROR', 'Permission key is required', status: :bad_request) if permission_key.blank?

    target_user = @user || current_user
    account_user = target_user.account_users.find_by(account: Current.account)
    return error_response('NOT_FOUND', 'User not found in this account', status: :not_found) unless account_user

    has_permission = Rails.cache.fetch(
      permission_cache_key(target_user.id, Current.account.id, permission_key),
      expires_in: AUTHZ_CACHE_TTL
    ) do
      Current.account.check_permission(permission_key, target_user)
    end
    
    success_response(data: {
      permission_key: permission_key,
      has_permission: has_permission,
      role: account_user.role_data,
      account_id: Current.account.id
    }, message: has_permission ? 'Permission granted' : 'Permission denied')
  end

  def role
    target_user = @user || current_user
    account_user = target_user.account_users.find_by(account: Current.account)
    return error_response('NOT_FOUND', 'User not found in this account', status: :not_found) unless account_user

    role_data = Rails.cache.fetch(
      role_cache_key(target_user.id, Current.account.id),
      expires_in: AUTHZ_CACHE_TTL
    ) do
      account_user.role_data
    end

    success_response(
      data: {
      role: role_data
      },
      message: 'User role retrieved successfully'
    )
  end

  private

  def update_user_role(role_key, account_user)
    # Try to find custom role first, then system role
    custom_role = Current.account.account_custom_roles.find_by(key: role_key)
    system_role = Role.find_by(key: role_key) unless custom_role

    if custom_role.nil? && system_role.nil?
      Rails.logger.error "Role '#{role_key}' not found. Available system roles: #{Role.pluck(:key)}, Available custom roles: #{Current.account.account_custom_roles.pluck(:key)}"
      raise ActiveRecord::RecordNotFound, "Role '#{role_key}' not found"
    end

    if custom_role
      # Atualizar account_custom_role_id no account_user (custom role)
      account_user.update!(
        account_custom_role_id: custom_role.id,
        role_id: nil  # Clear system role
      )

      # Remove user_roles entries for account roles (custom roles don't use user_roles)
      account_roles = @user.user_roles.joins(:role).where(roles: { system: false })
      account_roles.destroy_all
    else
      # Atualizar role_id no account_user (system role)
      account_user.update!(
        role_id: system_role.id,
        account_custom_role_id: nil  # Clear custom role
      )

      # Remover apenas as roles de conta (account roles), mantendo roles do sistema (system roles)
      account_roles = @user.user_roles.joins(:role).where(roles: { system: false })
      account_roles.destroy_all

      # Atribuir nova role de conta na user_roles
      # O find_or_create_by garante que não haverá duplicatas
      UserRole.assign_role_to_user(@user, system_role, current_user)
    end
  end

  def check_authorization
    # Verificar se usuário tem permissão para gerenciar usuários da conta
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
      # Padrão: accountId pode vir do header account-id ou params[:account_id]
      account_id = request.headers['account-id'] || params[:account_id] || Current.account&.id
      authorize_resource!('users', required_permission.split('.').last, account_id)
    else
      true # Para ações não mapeadas, permitir por enquanto
    end
  end

  def fetch_user
    @user = users.find(params[:id])
  end

  def account_user_attributes
    [:availability, :auto_offline]
  end

  def allowed_user_params
    [:name, :email, :role, :availability, :auto_offline, :password]
  end

  def user_params
    # Como os parâmetros vêm diretamente no nível raiz
      params.permit(allowed_user_params)
  end

  def new_user_params
    # Como os parâmetros vêm diretamente no nível raiz, usar permit diretamente
    params.permit(:email, :name, :role, :availability, :auto_offline, :password)
  end

  def users
    @users ||= Current.account.users.order_by_full_name.includes(:account_users)
  end

  def validate_limit_for_bulk_create
    available_count = available_agent_count
    # Se o limite for ilimitado (Infinity), sempre permitir
    return if available_count == Float::INFINITY

    limit_available = params[:emails].count <= available_count
    render_payment_required('Account limit exceeded. Please purchase more licenses') unless limit_available
  end

  def validate_limit
    render_payment_required('Account limit exceeded. Please purchase more licenses') unless can_add_agent?
  end

  def available_agent_count
    agent_limit = Current.account.feature_value("max_agents_per_account_crm").to_i
    # Se o limite for nil, 0 ou >= 1000, é considerado ilimitado
    return Float::INFINITY if agent_limit.nil? || agent_limit == 0

    logger.debug "Agent limit: #{agent_limit}, Current agents count: #{agents.count}"
    agent_limit - agents.count.to_i
  end

  def can_add_agent?
    available_agent_count.positive?
  end

  def delete_user_record(agent)
    # Placeholder for delete job
    # DeleteObjectJob.perform_later(agent) if agent.reload.account_users.blank?
    Rails.logger.info "Deleting user record for #{agent.email}" if agent.reload.account_users.blank?
  end

  def agents
    Current.account.agents
  end

  def user_data(user)
    account_user = user.account_users.find_by(account: Current.account)
    {
      id: user.id,
      name: user.name,
      email: user.email,
      confirmed: user.confirmed?,
      role: account_user&.role_data,  # Use account_user.role_data to get correct role (system or custom)
      availability: account_user&.availability,
      auto_offline: account_user&.auto_offline,
      active_at: account_user&.active_at,
      pubsub_token: user.pubsub_token,
      created_at: user.created_at,
      updated_at: user.updated_at
    }
  end

  def render_payment_required(message)
    error_response('OPERATION_FAILED', message, status: :payment_required)
  end

  def permission_cache_key(user_id, account_id, permission_key)
    "authz:account_permission:user=#{user_id}:account=#{account_id}:permission=#{permission_key}"
  end

  def role_cache_key(user_id, account_id)
    "authz:account_role:user=#{user_id}:account=#{account_id}"
  end
end
