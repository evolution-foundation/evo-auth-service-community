class Api::V1::AuthController < Api::BaseController
  include AccountSerializerHelper
  include AuthHelper
  include LicensingSetupConcern

  skip_before_action :authenticate_request!, only: [:login, :refresh, :register, :forgot_password, :reset_password, :validate, :verify_mfa, :confirmation, :resend_confirmation, :keycloak_exchange, :keycloak_refresh]

  # Login
  def login
    # Tenta encontrar o usuário pelo email
    email = params[:email]&.strip&.downcase
    user = User.from_email(email)

    if user&.valid_password?(params[:password])
      # Barreira de confirmação de e-mail: OPT-IN via REQUIRE_EMAIL_CONFIRMATION.
      # Default OFF para não quebrar instalações existentes; o nosso docker liga.
      # Quando ON, usuário não-confirmado não acessa (retorna code próprio p/ o
      # front oferecer reenvio).
      if require_email_confirmation? && !user.active_for_authentication?
        return error_response(
          'EMAIL_NOT_CONFIRMED',
          'Confirme seu e-mail para acessar.',
          details: [{ email: user.email }],
          status: :forbidden
        )
      end

      if user.mfa_enabled?
        render_mfa_required(user)
      else
        render_successful_login(user)
      end
    else
      render_invalid_credentials
    end
  end

  # Reenvia o e-mail de confirmação. PÚBLICO (o user não-confirmado não loga, então
  # não pode usar o endpoint autenticado de profiles). Resposta genérica anti-enumeração.
  def resend_confirmation
    email = params[:email]&.strip&.downcase
    user = User.from_email(email) if email.present?
    user.send_confirmation_instructions if user && !user.confirmed?
    success_response(
      data: {},
      message: 'Se o e-mail existir e não estiver confirmado, enviamos um novo link.'
    )
  end

  def logout
    # 1. Revoke token from bearer/cookie sent by frontend
    token_payload = @validation_result&.dig(:data, :token)
    if token_payload.present?
      token_type = token_payload[:type]
      
      case token_type
      when 'bearer'
        if @doorkeeper_token
          @doorkeeper_token.revoke
        end
      when 'api_access_token'
        if @access_token
          @access_token.destroy
        end
      end
    end

    # 2. Revoke refresh token from cookie if exists
    refresh_token = cookies[:_evo_rt]
    if refresh_token.present?
      token = Doorkeeper::AccessToken.find_by(refresh_token: refresh_token)
      token&.revoke
    end

    # 3. Revoke ALL active tokens related to the user to prevent refresh
    if current_user
      invalidate_user_tokens(current_user)
    end

    # 4. Clear HttpOnly cookies with correct paths
    # Detecta se está usando HTTPS (incluindo via ngrok)
    is_secure = request.ssl? || 
                request.headers['X-Forwarded-Proto'] == 'https' ||
                request.headers['X-Forwarded-Ssl'] == 'on' ||
                request.scheme == 'https'
    
    # Delete refresh token cookie (path atualizado para corresponder ao set_refresh_cookie)
    cookies.delete(:_evo_rt, 
                  secure: is_secure, 
                  httponly: true, 
                  same_site: is_secure ? :none : :lax, 
                  domain: cookie_domain,
                  path: '/api/v1/auth')
    
    # Delete access token cookie (default path)
    cookies.delete(:_evo_at, 
                  secure: is_secure, 
                  httponly: true, 
                  same_site: is_secure ? :none : :lax, 
                  domain: cookie_domain)

    keycloak_logout_url = nil
    if current_user&.keycloak_id_token.present?
      frontend_url = ENV.fetch('FRONTEND_URL', request.headers['Origin'])
      keycloak_logout_url = Keycloak::LogoutUrl.build(
        id_token_hint:  current_user.keycloak_id_token,
        post_logout_redirect_uri: "#{frontend_url}/login"
      )
      current_user.update_columns(keycloak_id_token: nil)
    end
    success_response(data: { keycloak_logout_url: keycloak_logout_url }, message: 'Logged out successfully')
  end

  def register
    create_user
  end

  def me
    account = RuntimeConfig.account
    accounts = account ? [account.merge('role' => current_user.role_data)] : []

    success_response(
      data: {
        user: UserSerializer.full(current_user),
        accounts: accounts
      },
      message: 'User profile retrieved successfully'
    )
  end

  def refresh
    result = process_refresh_token
    
    if result[:success]
      token = result[:token]
      user = User.find(token.resource_owner_id)
      new_token = create_oauth_token(user, token)
      set_refresh_cookie(new_token.refresh_token)
      set_access_token_cookie(new_token.token) if defined?(set_access_token_cookie)
      success_response(
        data: {
          access_token:   new_token.token,
          expires_in:     new_token.expires_in,
          token_type:     'Bearer',
          setup_active: Licensing::Runtime.context&.active? || false
        },
        message: 'Token refreshed successfully'
      )
    else
      error_response('UNAUTHORIZED', result[:error] || 'Token refresh failed', status: :unauthorized)
    end
  end

  def validate
    token_validator = TokenValidationService.new(request)
    result = token_validator.validate!

    account = RuntimeConfig.account
    accounts = account ? [account.merge('role' => result[:user][:role])] : []

    success_response(
      data: result.merge(accounts: accounts),
      message: 'Token validated successfully'
    )
  rescue TokenValidationService::InvalidToken => e
    error_response('INVALID_TOKEN', e.message, status: :unauthorized)
  rescue TokenValidationService::ExpiredToken => e
    error_response('EXPIRED_TOKEN', e.message, status: :unauthorized)
  rescue TokenValidationService::TokenNotFound => e
    error_response('TOKEN_NOT_FOUND', e.message, status: :unauthorized)
  end

  def forgot_password
    email = params[:email]&.strip&.downcase
    
    return error_response('VALIDATION_ERROR', 'Email is required', status: :unprocessable_entity) if email.blank?
    
    user = User.from_email(email)
    
    if user
      begin
        raw_token, encrypted_token = Devise.token_generator.generate(User, :reset_password_token)
        user.reset_password_token = encrypted_token
        user.reset_password_sent_at = Time.current
        
        if user.save(validate: false)
          # Tentar enviar email e capturar erros
          user.send_reset_password_instructions(
            email: email,
            provider: 'email',
            redirect_url: params[:redirect_url] || "#{ENV.fetch('FRONTEND_URL', 'http://localhost:5173')}/auth/reset-password",
            client_config: params[:config_name],
            token: raw_token
          )
          
          Rails.logger.info "Password reset email sent successfully to #{email}"
          
          success_response(
            data: { success: true },
            message: 'Password reset instructions have been sent to your email'
          )
        else
          Rails.logger.error "Failed to save reset token for user #{user.id}"
          error_response('OPERATION_FAILED', 'Failed to process password reset request', status: :unprocessable_entity)
        end
      rescue StandardError => e
        # Rollback: limpar token se envio falhou
        user.update_columns(reset_password_token: nil, reset_password_sent_at: nil) if user.persisted?
        
        Rails.logger.error "Failed to send password reset email to #{email}: #{e.class} - #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")
        
        error_response(
          'EMAIL_DELIVERY_FAILED',
          'Unable to send password reset email. Please contact support or try again later.',
          status: :service_unavailable
        )
      end
    else
      Rails.logger.info "Password reset requested for non-existent email: #{email}"
      
      success_response(
        data: { success: true },
        message: 'If an account exists with this email, password reset instructions will be sent'
      )
    end
  end

  def verify_mfa
    email = params[:email]
    code = params[:code]
    temp_token = params[:temp_token]

    unless email.present? && code.present? && temp_token.present?
      return error_response('VALIDATION_ERROR', 'Missing required parameters', status: :bad_request)
    end

    user = User.from_email(email)

    unless user&.mfa_enabled?
      return render_invalid_credentials
    end

    unless verify_temp_mfa_token(temp_token, user)
      return error_response('UNAUTHORIZED', 'Invalid or expired session', status: :unauthorized)
    end

    if user.mfa_locked?
      return error_response('LOCKED', 'Account temporarily locked due to too many failed attempts', status: :locked)
    end

    success = case user.mfa_method.to_sym
              when :totp
                user.validate_otp(code)
              when :email
                user.validate_email_otp(code)
              else
                false
              end

    if success
      user.reset_failed_mfa_attempts!
      render_successful_login(user)
    else
      user.record_failed_mfa_attempt!
      error_response(
        'INVALID_CODE',
        'Invalid verification code',
        status: :unprocessable_entity
      )
    end
  end

  def confirmation
    token = params[:confirmation_token]

    return error_response('VALIDATION_ERROR', 'Confirmation token is required', status: :unprocessable_entity) if token.blank?

    user = User.confirm_by_token(token)

    if user.errors.empty?
      success_response(
        data: { confirmed: true, email: user.email },
        message: 'Email confirmed successfully'
      )
    else
      error_response(
        'INVALID_TOKEN',
        user.errors.full_messages.join(', '),
        status: :unprocessable_entity
      )
    end
  end

  def reset_password
    token = params[:reset_password_token]
    password = params[:password]
    password_confirmation = params[:password_confirmation]
    
    return error_response('VALIDATION_ERROR', 'Reset password token is required', status: :unprocessable_entity) if token.blank?
    return error_response('VALIDATION_ERROR', 'Password is required', status: :unprocessable_entity) if password.blank?
    return error_response('VALIDATION_ERROR', 'Password confirmation is required', status: :unprocessable_entity) if password_confirmation.blank?
    
    if password != password_confirmation
      return error_response(
        'VALIDATION_ERROR',
        'Password confirmation does not match',
        details: [{ field: 'password_confirmation', message: 'does not match password' }],
        status: :unprocessable_entity
      )
    end
    
    user = User.with_reset_password_token(token)
    
    if user.blank?
      return error_response(
        'INVALID_TOKEN',
        'Invalid or expired reset password token',
        details: [{ field: 'reset_password_token', message: 'is invalid or expired' }],
        status: :unprocessable_entity
      )
    end
    
    if user.reset_password_period_valid?
      user.password = password
      user.password_confirmation = password_confirmation
      user.reset_password_token = nil
      user.reset_password_sent_at = nil
      
      if user.save
        active_tokens = Doorkeeper::AccessToken.where(resource_owner_id: user.id, revoked_at: nil)
        active_tokens.pluck(:token).each { |t| TokenValidationService.invalidate_cache_for_token(t) }
        active_tokens.update_all(revoked_at: Time.current)
        
        success_response(
          data: { success: true },
          message: 'Your password has been reset successfully. Please log in with your new password.'
        )
      else
        error_response(
          'VALIDATION_ERROR',
          user.errors.full_messages.join(', '),
          details: validation_error_details(user),
          status: :unprocessable_entity
        )
      end
    else
      error_response(
        'EXPIRED_TOKEN',
        'Reset password token has expired. Please request a new one',
        details: [{ field: 'reset_password_token', message: 'has expired' }],
        status: :unprocessable_entity
      )
    end
  end

  def keycloak_exchange
    unless ENV['KEYCLOAK_ENABLED'] == 'true'
      return error_response('KEYCLOAK_NOT_CONFIGURED', 'Keycloak integration is not enabled', status: :not_implemented)
    end

    kc_tokens = if params[:code].present?
                  Keycloak::CodeExchanger.exchange(
                    code:          params[:code],
                    code_verifier: params[:code_verifier],
                    redirect_uri:  params[:redirect_uri]
                  )
                else
                  { access_token: params[:keycloak_token].presence }
                end
    raw_token = kc_tokens[:access_token]
    id_token = kc_tokens[:id_token]

    return error_response('MISSING_TOKEN', 'code or keycloak_token param is required', status: :bad_request) unless raw_token

    claims = Keycloak::JwtValidator.verify(raw_token)
    user   = Keycloak::UserProvisioner.provision!(claims)

    kc_updates = {}
    kc_updates[:keycloak_id_token] = id_token if id_token.present?
    if kc_tokens[:refresh_token].present?
      kc_updates[:keycloak_refresh_token] = kc_tokens[:refresh_token]
      if kc_tokens[:refresh_expires_in].present?
        kc_updates[:keycloak_refresh_token_expires_at] = Time.current + kc_tokens[:refresh_expires_in].to_i.seconds
      end
    end
    user.update_columns(kc_updates) if kc_updates.any?

    render_successful_login(user)
  rescue Keycloak::CodeExchanger::Error => e
    error_response('TOKEN_EXCHANGE_FAILED', e.message, status: :bad_gateway)
  rescue Keycloak::JwtValidator::Error => e
    error_response('INVALID_TOKEN', e.message, status: :unauthorized)
  rescue ActiveRecord::RecordInvalid => e
    error_response('VALIDATION_ERROR', e.message, status: :unprocessable_entity)
  end

  def keycloak_refresh
    unless ENV['KEYCLOAK_ENABLED'] == 'true'
      return error_response('KEYCLOAK_NOT_CONFIGURED', 'Keycloak integration is not enabled', status: :not_implemented)
    end

    refresh_token = params[:keycloak_refresh_token].presence || cookies[:_evo_kc_rt]

    unless refresh_token.present?
      return error_response('MISSING_TOKEN', 'keycloak_refresh_token param is required', status: :bad_request)
    end

    kc_tokens = Keycloak::TokenRefresher.refresh(refresh_token: refresh_token)
    raw_token  = kc_tokens[:access_token]
    id_token   = kc_tokens[:id_token]

    claims = Keycloak::JwtValidator.verify(raw_token)
    user   = Keycloak::UserProvisioner.provision!(claims)

    kc_updates = {}
    kc_updates[:keycloak_id_token] = id_token if id_token.present?
    if kc_tokens[:refresh_token].present?
      kc_updates[:keycloak_refresh_token] = kc_tokens[:refresh_token]
      if kc_tokens[:refresh_expires_in].present?
        kc_updates[:keycloak_refresh_token_expires_at] = Time.current + kc_tokens[:refresh_expires_in].to_i.seconds
      end
    end
    user.update_columns(kc_updates) if kc_updates.any?

    render_successful_login(user)
  rescue Keycloak::TokenRefresher::ExpiredError => e
    error_response('REFRESH_TOKEN_EXPIRED', e.message, status: :unauthorized)
  rescue Keycloak::TokenRefresher::Error => e
    error_response('TOKEN_REFRESH_FAILED', e.message, status: :bad_gateway)
  rescue Keycloak::JwtValidator::Error => e
    error_response('INVALID_TOKEN', e.message, status: :unauthorized)
  rescue ActiveRecord::RecordInvalid => e
    error_response('VALIDATION_ERROR', e.message, status: :unprocessable_entity)
  end

  private

  def validation_error_details(user)
    user.errors.map do |error|
      {
        field: error.attribute.to_s,
        message: error.message
      }
    end
  end

  def render_mfa_required(user)
    temp_token = generate_temp_mfa_token(user)

    # Send email code if email MFA method
    if user.mfa_method == 'email'
      code = user.generate_email_otp
      UserMailer.two_factor_authentication_code(user, code).deliver_later
    end

    success_response(
      data: {
        mfa_required: true,
        mfa_method: user.mfa_method,
        temp_token: temp_token,
        email: user.email
      },
      message: 'MFA verification required',
      status: :accepted
    )
  end

  def generate_temp_mfa_token(user)
    payload = {
      user_id: user.id,
      email: user.email,
      exp: 10.minutes.from_now.to_i
    }
    JWT.encode(payload, Rails.application.secret_key_base)
  end

  def verify_temp_mfa_token(token, user)
    return false unless token.present?

    decoded = JWT.decode(token, Rails.application.secret_key_base)[0]
    decoded['user_id'] == user.id && decoded['email'] == user.email
  rescue JWT::DecodeError, JWT::ExpiredSignature
    false
  end

  def render_successful_login(user)
    attempt_setup(user)
    invalidate_user_tokens(user)

    # Create new OAuth token
    oauth_token = create_oauth_token(user)
    
    # Set refresh token in HttpOnly cookie
    set_refresh_cookie(oauth_token.refresh_token)
    set_access_token_cookie(oauth_token.token) if defined?(set_access_token_cookie)

    # Define o current_user para uso nos métodos do helper
    @current_user = user
    @doorkeeper_token = oauth_token

    # Agora podemos chamar os métodos do helper
    render_user_validation_success
  end

  def render_invalid_credentials
    error_response('UNAUTHORIZED', 'Invalid email or password', status: :unauthorized)
  end
end
