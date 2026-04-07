class DeviseOverrides::SessionsController < DeviseTokenAuth::SessionsController
  include LicensingSetupConcern

  # Prevent session parameter from being passed
  # Unpermitted parameter: session
  wrap_parameters format: []
  before_action :process_sso_auth_token, only: [:create]

  def new
    # Redirect to new React frontend instead of old Vue.js interface
    redirect_to ENV.fetch('FRONTEND_URL', 'http://localhost:5173') + '/auth?error=access-denied', allow_other_host: true
  end

  def create
    # Authenticate user via the temporary sso auth token
    if params[:sso_auth_token].present? && @resource.present?
      authenticate_resource_with_sso_token
      yield @resource if block_given?
      render_create_success
    else
      # Standard authentication flow
      field = (resource_params.keys.map(&:to_sym) & resource_class.authentication_keys).first
      @resource = nil

      if field
        q_value = get_case_insensitive_field_from_resource_params(field)
        @resource = find_resource(field, q_value)
      end

      if @resource && valid_params?(field, q_value) && @resource.valid_password?(resource_params[:password])
        # Check if MFA is enabled
        if @resource.two_factor_enabled? && @resource.two_factor_setup_complete?
          handle_mfa_authentication
        else
          # Continue with normal authentication
          @token = @resource.create_token
          @resource.save!
          sign_in(:user, @resource, store: false, bypass: false)
          yield @resource if block_given?
          render_create_success
        end
      else
        render_create_error_bad_credentials
      end
    end
  end

  def render_create_success
    attempt_setup(@resource)

    # Get token from @token created by DeviseTokenAuth
    token_string = @token&.token || @resource.tokens&.values&.first&.dig('token')

    render json: {
      data: ::Serializers::UserSerializer.full(
        @resource,
        include_access_token: true,
        include_account_context: true,
        include_accounts: true,
        token: token_string
      )
    }
  end

  private

  def handle_mfa_authentication
    # Generate temporary token for MFA verification
    temp_token = generate_temp_mfa_token(@resource)

    # Send email code if email MFA is enabled
    if @resource.mfa_method == 'email'
      code = @resource.generate_email_otp
      UserMailer.two_factor_authentication_code(@resource, code).deliver_later
    end

    render json: {
      requires_mfa: true,
      mfa_method: @resource.mfa_method,
      temp_token: temp_token,
      email: @resource.email
    }, status: :ok
  end

  def generate_temp_mfa_token(user)
    # Generate a temporary JWT token valid for 10 minutes
    payload = {
      user_id: user.id,
      email: user.email,
      exp: 10.minutes.from_now.to_i
    }
    JWT.encode(payload, Rails.application.secret_key_base)
  end

  def login_page_url(error: nil)
    frontend_url = ENV.fetch('FRONTEND_URL', nil)

    "#{frontend_url}/app/login?error=#{error}"
  end

  def authenticate_resource_with_sso_token
    @token = @resource.create_token
    @resource.save!

    sign_in(:user, @resource, store: false, bypass: false)
    # invalidate the token after the user is signed in
    @resource.invalidate_sso_auth_token(params[:sso_auth_token])
  end

  def process_sso_auth_token
    return if params[:email].blank?

    user = User.from_email(params[:email])
    @resource = user if user&.valid_sso_auth_token?(params[:sso_auth_token])
  end
end
