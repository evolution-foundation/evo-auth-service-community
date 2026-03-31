module AuthHelper
  extend ActiveSupport::Concern
  
  included do
    include AccountSerializerHelper if defined?(AccountSerializerHelper)
  end

  OAUTH_CONFIG = {
    uid: 'evo-auth-service',
    name: 'Evo Auth Service',
    scopes: 'read write'
  }.freeze

  def send_auth_headers(user)
    invalidate_user_tokens(user)
    
    # Generate new token for the user
    token = create_oauth_token(user)
    
    # Set the headers for token authentication
    response.headers.merge!(token) if token
  end



  def create_oauth_token(user, token = nil)
    # Find or create OAuth application
    application = OauthApplication.find_or_create_by(
      name: OAUTH_CONFIG[:name],
      uid: OAUTH_CONFIG[:uid],
      scopes: OAUTH_CONFIG[:scopes],
      trusted: true
    ) do |app|
      app.secret = SecureRandom.uuid
      app.redirect_uri = 'urn:ietf:wg:oauth:2.0:oob'
      app.confidential = true
    end
    
    previous_refresh_token = ''

    if token.present?
      previous_refresh_token = token.refresh_token if token.refresh_token.present?
      TokenValidationService.invalidate_cache_for_token(token.token) if token.token.present?
      token.revoke
    end

    # Create access token with JWT format and pass resource_owner directly
    Doorkeeper::AccessToken.create!(
      application: application,
      resource_owner_id: user.id,
      expires_in: Doorkeeper.configuration.access_token_expires_in,
      scopes: 'read write',
      use_refresh_token: true,
      previous_refresh_token: previous_refresh_token
    )
  end

  def invalidate_user_tokens(user)
    # Bust validation cache before revoking
    active_tokens = Doorkeeper::AccessToken.where(resource_owner_id: user.id, revoked_at: nil)
    active_tokens.pluck(:token).each { |t| TokenValidationService.invalidate_cache_for_token(t) }

    # Revoke all existing tokens for this user
    active_tokens.each(&:revoke)
  end

  def is_secure_request?
    # Detecta se está usando HTTPS (incluindo via ngrok)
    request.ssl? || 
    request.headers['X-Forwarded-Proto'] == 'https' ||
    request.headers['X-Forwarded-Ssl'] == 'on' ||
    request.scheme == 'https'
  end

  def set_refresh_cookie(refresh_token)
    is_secure = is_secure_request?
    domain = cookie_domain
    
    # Debug logs
    Rails.logger.info "AuthHelper: Setting refresh cookie"
    Rails.logger.info "AuthHelper: Request host: #{request.host}"
    Rails.logger.info "AuthHelper: Cookie domain: #{domain.inspect}"
    Rails.logger.info "AuthHelper: Is secure: #{is_secure}"
    Rails.logger.info "AuthHelper: SameSite: #{is_secure ? :none : :lax}"
    
    cookie_options = {
      value: refresh_token,
      httponly: true,
      secure: is_secure,
      samesite: is_secure ? :none : :lax, # :none requer secure: true para funcionar
      path: '/api/v1/auth', # Path mais amplo para incluir refresh e outros endpoints
    }
    
    # Só adiciona domain se não for nil
    cookie_options[:domain] = domain if domain.present?
    
    cookies[:_evo_rt] = cookie_options
    
    Rails.logger.info "AuthHelper: Cookie set with options: #{cookie_options.except(:value).inspect}"
  end
  
  def set_access_token_cookie(access_token)
    is_secure = is_secure_request?
    
    cookies[:_evo_at] = {
      value: access_token,
      httponly: true,
      secure: is_secure,
      samesite: is_secure ? :none : :lax, # :none requer secure: true para funcionar
      domain: cookie_domain
    }
  end
  
  def cookie_domain
    request_host = request.host
    
    # Em desenvolvimento com ngrok, NÃO definir domain para permitir cookies funcionarem
    # quando frontend e auth service usam o mesmo domínio ngrok
    # Cookies não podem ser compartilhados entre domínios diferentes do ngrok
    # (ex: evo-app-davidson.ngrok.app e evo-auth-davidson.ngrok.app)
    if Rails.env.development?
      # Para ngrok, não definir domain - cookie será específico do domínio
      # Isso permite que funcione quando ambos os serviços usam o mesmo domínio
      if request_host.include?('ngrok')
        return nil
      end
      # Para localhost, não definir domain
      return nil if request_host == 'localhost' || request_host =~ /\A\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\z/
    end
    
    # Em produção, usar lógica normal de domínio
    return nil if Rails.env.test?
    
    # Verifica se o host é um IP ou localhost
    return nil if request_host =~ /\A\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\z/ || request_host == 'localhost'
    
    # Extrai o domínio principal para definir cookies entre subdomínios
    domain_parts = request_host.split('.')
    
    # Para garantir que não definimos cookies para TLDs genéricos
    if domain_parts.size >= 2
      # Retorna os dois últimos segmentos do domínio (ex: example.com)
      ".#{domain_parts[-2]}.#{domain_parts[-1]}"
    else
      # Fallback para o host completo se não conseguirmos determinar o domínio principal
      request_host
    end
  end

  def render_unauthorized(message = 'Unauthorized')
    error_response('UNAUTHORIZED', message, status: :unauthorized)
  end

  def process_refresh_token
    # Debug: Log todos os cookies recebidos
    Rails.logger.info "AuthHelper: All cookies received: #{cookies.to_hash.keys.inspect}"
    Rails.logger.info "AuthHelper: Request origin: #{request.headers['Origin']}"
    Rails.logger.info "AuthHelper: Request host: #{request.host}"
    Rails.logger.info "AuthHelper: Request scheme: #{request.scheme}"
    Rails.logger.info "AuthHelper: Is secure?: #{is_secure_request?}"
    
    # Tenta obter refresh token do cookie primeiro
    refresh_token = cookies[:_evo_rt]
    
    # Se não encontrar no cookie, tenta obter do header Authorization como fallback
    # Isso permite que funcione mesmo quando cookies não são compartilhados entre domínios diferentes do ngrok
    if refresh_token.blank?
      auth_header = request.headers['Authorization'] || request.headers['authorization']
      Rails.logger.info "AuthHelper: Authorization header present?: #{auth_header.present?}"
      Rails.logger.info "AuthHelper: Authorization header value (first 30 chars): #{auth_header&.[](0..29)}" if auth_header.present?
      
      if auth_header&.start_with?('Bearer ')
        # Tenta usar o token do header como refresh token (fallback para desenvolvimento com ngrok)
        potential_refresh_token = auth_header.sub('Bearer ', '').strip
        Rails.logger.info "AuthHelper: Cookie not found, trying header token as refresh token"
        refresh_token = potential_refresh_token
      elsif auth_header.present?
        Rails.logger.warn "AuthHelper: Authorization header present but doesn't start with 'Bearer '"
      end
    end
    
    Rails.logger.info "AuthHelper: Refresh token cookie present?: #{cookies[:_evo_rt].present?}"
    Rails.logger.info "AuthHelper: Refresh token from header?: #{refresh_token.present? && cookies[:_evo_rt].blank?}"
    Rails.logger.info "AuthHelper: Refresh token value (first 20 chars): #{refresh_token&.[](0..19)}" if refresh_token.present?
    
    if refresh_token.blank?
      Rails.logger.warn "AuthHelper: Refresh token not found in cookies or header"
      return { success: false, error: 'Refresh token not found' }
    end

    token = Doorkeeper::AccessToken.find_by(refresh_token: refresh_token)
    
    # Se não encontrar pelo refresh_token, tenta encontrar pelo token (para fallback)
    if token.nil? && refresh_token.present?
      token = Doorkeeper::AccessToken.find_by(token: refresh_token)
      if token
        Rails.logger.info "AuthHelper: Found token by access token (fallback mode)"
        # Usa o refresh_token do token encontrado
        refresh_token = token.refresh_token
      end
    end
    
    # Verifica se o token existe
    unless token
      Rails.logger.warn "AuthHelper: Token not found in database for refresh token"
      return { success: false, error: 'Invalid refresh token' }
    end
          
    # Verifica se o refresh token está expirado usando o método que adicionamos
    if token.refresh_token_expired?
      Rails.logger.warn "AuthHelper: Refresh token expired"
      return { success: false, error: 'Refresh token expired' }
    end

    Rails.logger.info "AuthHelper: Refresh token validated successfully for user #{token.resource_owner_id}"
    { success: true, token: token }
  end

  def render_invalid_credentials
    error_response('UNAUTHORIZED', 'Invalid email or password', status: :unauthorized)
  end

  # Method for complete validation of OAuth/JWT tokens
  def validate_oauth_token
    # Tenta obter o token do header de autorização
    raw_token = extract_token_from_header
    
    # Primeiro verifica se temos um token no header de autorização
    if raw_token.present?
      begin
        # Decode the JWT to validate its structure and signature
        payload = decode_jwt_token(raw_token)
        
        # Verify if the token was correctly decoded and has the necessary claims
        if payload.blank? || payload['sub'].blank? || payload['exp'].blank?
          render_unauthorized('Malformed token')
          return false
        end
        
        # Manually verify token expiration (double check)
        if Time.at(payload['exp']).utc < Time.now.utc
          render_unauthorized('Token expired')
          return false
        end
        
        # IMPORTANTE: Busca o token no banco de dados pelo token bruto
        @doorkeeper_token = Doorkeeper::AccessToken.find_by(token: raw_token)
        
        if @doorkeeper_token.nil?
          render_unauthorized('Token not found in database')
          return false
        end
        
        if @doorkeeper_token.revoked?
          render_unauthorized('Token revoked')
          return false
        end
        
        # Configura o current_user
        @current_user = User.find_by(id: @doorkeeper_token.resource_owner_id)
        
        unless @current_user
          render_unauthorized('User not found')
          return false
        end
        
        # Verify if the user ID in the token matches the ID of the authenticated user
        unless payload['sub'].to_s == @current_user.id.to_s
          render_unauthorized('Token does not belong to this user')
          return false
        end
        
        # Validate if the token scope is adequate for the operation
        unless (@doorkeeper_token.scopes.to_a & ['read', 'write']).present?
          render_unauthorized('Insufficient scopes in token')
          return false
        end
        
        # Update the user's last access
        @current_user.update_column(:last_sign_in_at, Time.current) if @current_user.respond_to?(:last_sign_in_at)
        
        Rails.logger.info "AuthHelper: Successfully authenticated via Bearer token for user #{@current_user.id}"
        return true
      rescue JWT::DecodeError => e
        Rails.logger.error "JWT Decode error: #{e.message}"
        # Não retornar aqui, tentar autenticar via cookie
      rescue StandardError => e
        Rails.logger.error "Error validating Bearer token: #{e.message}"
        # Não retornar aqui, tentar autenticar via cookie
      end
    end
    
    # Se não tem token no header ou a validação falhou, tente usar o refresh token no cookie
    refresh_token = cookies[:_evo_rt]
    
    if refresh_token.present?
      # Log para debug
      Rails.logger.info "AuthHelper: Using refresh token from cookie: #{refresh_token[0..10]}..."
      
      token = Doorkeeper::AccessToken.find_by(refresh_token: refresh_token)
      
      if token && !token.revoked_at
        user = User.find_by(id: token.resource_owner_id)
        
        if user
          # Atualiza o current_user e doorkeeper_token para uso posterior
          @current_user = user
          @doorkeeper_token = token
          
          # Validate if the token scope is adequate for the operation
          unless (@doorkeeper_token.scopes.to_a & ['read', 'write']).present?
            render_unauthorized('Insufficient scopes in token')
            return false
          end
          
          # Update the user's last access
          @current_user.update_column(:last_sign_in_at, Time.current) if @current_user.respond_to?(:last_sign_in_at)
          
          Rails.logger.info "AuthHelper: Successfully authenticated via refresh token cookie for user #{user.id}"
          return true
        end
      end
    end
    
    render_unauthorized('Authentication failed: No valid token found')
    return false
  end
  
  # Method to decode the JWT token
  def decode_jwt_token(token)
    # Get the public/secret key configured in Doorkeeper
    secret = Doorkeeper::JWT.configuration.secret_key
    
    # Decoding options (verify exp, iss, etc)
    options = {
      algorithm: Doorkeeper::JWT.configuration.signing_method,
      verify_iat: true,
      verify_expiration: true,
      required_claims: ['sub', 'exp']
    }

    # Decode the token
    decoded_token = JWT.decode(token, secret, true, options)
    
    # Return the payload (first element of the array)
    decoded_token.first
  end
  
  # Method to extract the token from the Authorization header
  def extract_token_from_header
    auth_header = request.headers['Authorization']
    return unless auth_header&.start_with?('Bearer ')
    
    auth_header.split.last
  end
  
  # Method to generate successful token validation response for regular user
  def render_user_validation_success
    account = RuntimeConfig.account
    accounts = account ? [account.merge('role' => current_user.role_data)] : []

    success_response(
      data: {
        user: UserSerializer.full(current_user),
        accounts: accounts,
        token: token
      },
      message: 'Login successful'
    )
  end
  
  # Method to get information about the current token
  def token
    if @doorkeeper_token
      {
        access_token: @doorkeeper_token.token,
        scopes: @doorkeeper_token.scopes.to_a,
        expires_in: @doorkeeper_token.expires_in,
        created_at: Time.at(@doorkeeper_token.created_at).iso8601,
        setup_active: Licensing::Runtime.context&.active? || false
      }
    elsif @access_token
      {
        access_token: @access_token.token,
        scopes: @access_token.scopes, # AccessToken has default scopes
      }
    else
      {}
    end
  end

  # Method to generate successful token validation response for AccessToken
  def render_access_token_validation_success
    account = RuntimeConfig.account
    accounts = account ? [account.merge('role' => current_user.role_data)] : []

    success_response(
      data: {
        user: UserSerializer.full(current_user),
        accounts: accounts,
        token: token
      },
      message: 'Token validation successful'
    )
  end

  def create_user
    email = params[:email] || params.dig(:user, :email)
    password = params[:password] || params.dig(:user, :password)
    
    return error_response('VALIDATION_ERROR', 'Email and password are required', status: :unprocessable_entity) if email.blank? || password.blank?
    
    # Verificar se usuário já existe
    existing_user = User.from_email(email)
    
    if existing_user
      # Se usuário já existe, validar senha
      if existing_user.valid_password?(password)
        # Senha correta: criar token OAuth e retornar usuário existente (permitindo registro em outro workspace)
        invalidate_user_tokens(existing_user)
        oauth_token = create_oauth_token(existing_user)
        
        success_response(
          data: { 
            user: UserSerializer.full(existing_user),
            token: {
              access_token: oauth_token.token,
              expires_in: oauth_token.expires_in,
              token_type: 'Bearer'
            }
          },
          message: 'User already exists and password is valid',
          status: :ok
        )
      else
        # Senha incorreta: retornar erro
        error_response('VALIDATION_ERROR', 'Email already registered with a different password', status: :unprocessable_entity)
      end
    else
      # Criar novo usuário
      if params[:user].blank? && params[:name].present? && params[:password].present?
        user_data = {
          name: params[:name],
          email: email,
          password: password,
          password_confirmation: params[:password_confirmation] || password
        }
      
        @user = User.new(user_data)
      else
        begin
          @user = User.new(user_params)
        rescue ActionController::ParameterMissing => e
          Rails.logger.error "Parameter missing: #{e.message}"
          return error_response('VALIDATION_ERROR', e.message, status: :unprocessable_entity)
        end
      end
      
      if params[:password].present?
        @user.password = params[:password]
        @user.password_confirmation = params[:password_confirmation] || params[:password]
      end
      
      if @user.save
        success_response(
          data: { user: UserSerializer.full(@user) },
          message: 'User created successfully',
          status: :created
        )
      else
        render_unprocessable_entity(@user.errors)
      end
    end
  end
end
