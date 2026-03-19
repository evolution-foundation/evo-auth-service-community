class Api::V1::AccountsController < Api::BaseController
  include AuthHelper
  include AccountSerializerHelper

  skip_before_action :authenticate_user!, :set_current_user, :handle_with_exception,
                     only: [:create], raise: false
  before_action :check_signup_enabled, only: [:create]
  before_action :ensure_account_name, only: [:create]
  before_action :validate_captcha, only: [:create]
  before_action :fetch_account, except: [:create, :active_plan]
  before_action :set_current_account, except: [:create, :active_plan]
  before_action :check_authorization, except: [:create]

  rescue_from CustomExceptions::Account::InvalidEmail,
              CustomExceptions::Account::InvalidParams,
              CustomExceptions::Account::UserExists,
              CustomExceptions::Account::UserErrors,
              with: :render_error_response

  def show
    success_response(
      data: AccountSerializer.full(@account, include_settings: true, include_attributes: true, include_features: true),
      message: 'Account retrieved successfully'
    )
  end

  def create
    @user, @account = AccountBuilder.new(
      account_name: account_params[:account_name],
      user_full_name: account_params[:user_full_name],
      email: account_params[:email],
      user_password: account_params[:password],
      locale: account_params[:locale],
      support_email: account_params[:support_email],
      user: current_user
    ).perform
    if @user
      attempt_setup(@user)
      success_response(
        data: {
          user: UserSerializer.full(@user),
          account: AccountSerializer.full(@account, include_settings: true, include_attributes: true)
        },
        message: 'Account created successfully',
        status: :created
      )
    else
      render_error_response(CustomExceptions::Account::SignupFailed.new({}))
    end
  end

  def update
    @account.assign_attributes(account_params.slice(:name, :locale, :domain, :support_email))
    @account.custom_attributes.merge!(custom_attributes_params)
    @account.settings.merge!(settings_params)
    @account.custom_attributes['onboarding_step'] = 'invite_team' if @account.custom_attributes['onboarding_step'] == 'account_update'
    @account.save!
    success_response(
      data: { account: AccountSerializer.full(@account, include_settings: true, include_attributes: true) },
      message: 'Account updated successfully'
    )
  end

  def update_active_at
    return error_response('NOT_FOUND', 'Account user not found', status: :not_found) unless @current_account_user

    @current_account_user.active_at = Time.now.utc
    @current_account_user.save!
    success_response(
      data: { active_at: @current_account_user.active_at },
      message: 'Account active timestamp updated successfully'
    )
  end

  def permissions
    # Retornar permissões do usuário logado para esta account
    account_user = current_user.account_users.find_by(account: @account)
    return error_response('NOT_FOUND', 'Account not found', status: :not_found) unless account_user

    success_response(
      data: {
        permissions: account_user.permissions,
        role: account_user.role_data,
      },
      message: 'Account permissions retrieved successfully'
    )
  end

  def active_plan
    # Plans removed in community edition — always returns nil
    success_response(
      data: { active_plan: nil },
      message: 'No active plan found'
    )
  end

  private

  def ensure_account_name
    # ensure that account_name and user_full_name is present
    # this is becuase the account builder and the models validations are not triggered
    # this change is to align the behaviour with the v2 accounts controller
    # since these values are not required directly there
    return if account_params[:account_name].present?
    return if account_params[:user_full_name].present?

    raise CustomExceptions::Account::InvalidParams.new({})
  end

  def fetch_account
    @account = current_user.accounts.find_by(id: params[:id])

    # Verificar se a account foi encontrada
    unless @account
      error_response('NOT_FOUND', 'Account not found', status: :not_found)
      return
    end

    @current_account_user = @account.account_users.find_by(user_id: current_user.id)
  end

  def set_current_account
    Current.account = @account if @account
  end

  def fetch_account_from_header
    account = Account.first
    @current_account_user = account&.account_users&.find_by(user_id: current_user.id)
    account
  end

  def account_params
    params.permit(:account_name, :email, :name, :password, :locale, :domain, :support_email, :user_full_name)
  end

  def custom_attributes_params
    params.permit(:industry, :company_size, :timezone)
  end

  def settings_params
    params.permit(:auto_resolve_after, :auto_resolve_message, :auto_resolve_ignore_waiting, :audio_transcriptions, :auto_resolve_label)
  end

  def attempt_setup(user)
    store = Licensing::Store.new

    if Licensing::Runtime.context&.active?
      store.load_or_create_instance_id
      store.load_runtime_data
      return
    end

    return if Licensing::Activation.try_reactivate(store: store)

    Licensing::Setup.perform(
      email:       user.email,
      name:        user.name.presence || user.email,
      instance_id: store.load_or_create_instance_id,
      version:     Licensing::Activation::VERSION,
      client_ip:   request.remote_ip
    )
  end

  def check_signup_enabled
    raise ActionController::RoutingError, 'Not Found' if GlobalConfig.get('ENABLE_ACCOUNT_SIGNUP', 'false') == 'false'
    return true if @current_user.present?
  end

  def validate_captcha
    # Placeholder for captcha validation
    # raise ActionController::InvalidAuthenticityToken, 'Invalid Captcha' unless EvolutionCaptcha.new(params[:h_captcha_client_response]).valid?
    true
  end

  def check_authorization
    # Verificar se usuário tem permissão para gerenciar accounts
    action_map = {
      'index' => 'accounts.read',
      'show' => 'accounts.read',
      'create' => 'accounts.create',
      'update' => 'accounts.update',
      'update_active_at' => 'accounts.update'
    }

    required_permission = action_map[action_name]
    if required_permission
      resource_key, action_key = required_permission.split('.')
      authorize_resource!(resource_key, action_key, params[:id])
    else
      # Log para ações não mapeadas
      Rails.logger.debug "Action '#{action_name}' not mapped to any permission in #{self.class.name}"
      true
    end
  end

  def pundit_user
    {
      user: current_user,
      account: @account,
      account_user: @current_account_user
    }
  end
end
