class DeviseOverrides::PasswordsController < DeviseTokenAuth::PasswordsController
  def create
    return render_create_error_missing_email unless resource_params[:email]

    @email = get_case_insensitive_field_from_resource_params(:email)
    @resource = find_resource(:email, @email)

    if @resource
      yield @resource if block_given?
      @resource.send_reset_password_instructions(
        email: @email,
        provider: 'email',
        redirect_url: @redirect_url,
        client_config: params[:config_name]
      )

      if @resource.errors.empty?
        render_create_success
      else
        render_create_error @resource.errors
      end
    else
      render_create_error_missing_resource
    end
  end

  def edit
    # Redirect to frontend reset password page
    frontend_url = ENV.fetch('FRONTEND_URL', 'http://localhost:5173')
    redirect_to "#{frontend_url}/auth/reset-password?reset_password_token=#{params[:reset_password_token]}", allow_other_host: true
  end

  private

  def render_create_success
    render json: {
      success: true,
      message: 'An email has been sent to your email address. Follow the directions in the email to change your password.'
    }
  end

  def render_create_error_missing_email
    render_error(422, I18n.t('devise_token_auth.passwords.missing_email'))
  end

  def render_create_error_missing_resource
    render_error(404, I18n.t('devise_token_auth.passwords.user_not_found', email: @email))
  end

  def render_create_error(errors)
    render json: {
      success: false,
      errors: errors
    }, status: :unprocessable_entity
  end
end
