class DeviseOverrides::OmniauthCallbacksController < DeviseTokenAuth::OmniauthCallbacksController
  # include EmailHelper # Not needed for evo-auth-service

  def omniauth_success
    get_resource_from_auth_hash

    @resource.present? ? sign_in_user : sign_up_user
  end

  private

  def sign_in_user
    @resource.skip_confirmation! if confirmable_enabled?

    # once the resource is found and verified
    # we can just send them to the login page again with the SSO params
    # that will log them in
    encoded_email = ERB::Util.url_encode(@resource.email)
    redirect_to login_page_url(email: encoded_email, sso_auth_token: @resource.generate_sso_auth_token)
  end

  def sign_up_user
    # return redirect_to login_page_url(error: 'no-account-found') unless account_signup_allowed? # Not needed for evo-auth-service
    # return redirect_to login_page_url(error: 'business-account-only') unless validate_signup_email_is_business_domain? # Not needed for evo-auth-service

    create_account_for_user
    token = @resource.send(:set_reset_password_token)
    frontend_url = ENV.fetch('FRONTEND_URL', 'http://localhost:5173')
    redirect_to "#{frontend_url}/auth/reset-password?reset_password_token=#{token}"
  end

  def login_page_url(error: nil, email: nil, sso_auth_token: nil)
    frontend_url = ENV.fetch('FRONTEND_URL', 'http://localhost:5173')
    params = { email: email, sso_auth_token: sso_auth_token }.compact
    params[:error] = error if error.present?

    "#{frontend_url}/auth?#{params.to_query}"
  end

  # def account_signup_allowed? # Not needed for evo-auth-service
  #   # set it to true by default, this is the behaviour across the app
  #   GlobalConfigService.load('ENABLE_ACCOUNT_SIGNUP', 'false') != 'false'
  # end

  def resource_class(_mapping = nil)
    User
  end

  def get_resource_from_auth_hash # rubocop:disable Naming/AccessorMethodName
    # find the user with their email instead of UID and token
    @resource = resource_class.where(
      email: auth_hash['info']['email']
    ).first
  end

  # def validate_signup_email_is_business_domain? # Not needed for evo-auth-service
  #   # ...
  # end

  def create_account_for_user
    admin_role = Role.find_by!(key: 'administrator')
    UserRole.assign_role_to_user(@resource, admin_role)
  end

  def default_devise_mapping
    'user'
  end
end
