# rubocop:disable Metrics/BlockLength
Doorkeeper.configure do
  # Change the ORM that doorkeeper will use (requires ORM extensions installed).
  # Check the list of supported ORMs here: https://github.com/doorkeeper-gem/doorkeeper#orms
  orm :active_record

  # This block will be called to check whether the resource owner is authenticated or not.
  resource_owner_authenticator do
    # Put your resource owner authentication logic here.
    # Example implementation:
    current_user || redirect_to(new_user_session_url)
  end

  # Custom application model
  application_class 'OauthApplication'

  # Define a custom method to authenticate the client
  # It can be used to pass extra information to applications
  resource_owner_from_credentials do |_routes|
    user = User.from_email(params[:username])
    user if user&.valid_password?(params[:password])
  end

  # Configure token expiration times from environment variables
  access_token_expires_in ENV.fetch('OAUTH_TOKEN_EXPIRES_IN', 7200).to_i.seconds
  
  # Configure authorization code expiration
  authorization_code_expires_in ENV.fetch('OAUTH_AUTHORIZATION_CODE_EXPIRES_IN', 600).to_i.seconds
  
  # Use refresh tokens (sliding sessions)
  use_refresh_token

  #Generator JWT
  access_token_generator '::Doorkeeper::JWT'

  # Define redirect uri with a custom way
  default_scopes  :read

  # Definir escopos disponíveis
  optional_scopes :read,
                  :write,
                  :'accounts:read',
                  :'accounts:write',
                  :'users:read',
                  :'users:write',
                  # Recursos principais
                  :'conversations:read',
                  :'conversations:write',
                  :'contacts:read',
                  :'contacts:write',
                  :'messages:read',
                  :'messages:write',
                  :'inboxes:read',
                  :'inboxes:write',
                  :'agents:read',
                  :'agents:write',
                  :'reports:read',
                  :'reports:write',
                  # Channels
                  :'channels:read',
                  :'channels:write',
                  :'channels:facebook:read',
                  :'channels:facebook:write',
                  :'channels:whatsapp:read',
                  :'channels:whatsapp:write',
                  :'channels:evolution:read',
                  :'channels:evolution:write',
                  :'channels:notificame:read',
                  :'channels:notificame:write',
                  :'channels:twilio:read',
                  :'channels:twilio:write',
                  :'channels:email:read',
                  :'channels:email:write',
                  # Automação
                  :'automation_rules:read',
                  :'automation_rules:write',
                  :'macros:read',
                  :'macros:write',
                  :'macros:execute',
                  # Organização
                  :'labels:read',
                  :'labels:write',
                  :'teams:read',
                  :'teams:write',
                  :'custom_attributes:read',
                  :'custom_attributes:write',
                  :'custom_attribute_definitions:read',
                  :'custom_attribute_definitions:write',
                  # Canned Responses
                  :'canned_responses:read',
                  :'canned_responses:write',
                  # Notificações
                  :'notifications:read',
                  :'notifications:write',

                  # Pipelines
                  :'pipelines:read',
                  :'pipelines:write',
                  :'pipeline_stages:read',
                  :'pipeline_stages:write',
                  :'pipeline_conversations:read',
                  :'pipeline_conversations:write',
                  # Integrations
                  :'integrations:read',
                  :'integrations:write',
                  :'webhooks:read',
                  :'webhooks:write',
                  :'dashboard_apps:read',
                  :'dashboard_apps:write',
                  # Admin
                  :admin

  # Forces the usage of the HTTPS protocol in non-native redirect uris (enabled
  # by default in non-development environments). OAuth2 delegates security in
  # communication to the HTTPS protocol so it is wise to keep this enabled.
  force_ssl_in_redirect_uri Rails.env.production?

  # Specify what grant flows are enabled in array of Strings. The valid
  # strings and the flows they enable are:
  #
  # "authorization_code" => Authorization Code Grant Flow
  # "implicit"           => Implicit Grant Flow
  # "password"           => Resource Owner Password Credentials Grant Flow
  # "client_credentials" => Client Credentials Grant Flow
  #
  grant_flows %w[authorization_code client_credentials password]

  # WWW-Authenticate Realm (default "Doorkeeper").
  realm 'Evolution API'

  # Configurar métodos para encontrar o token de acesso
  # Adiciona um método personalizado para ler tokens de cookies HttpOnly
  access_token_methods :from_bearer_authorization, :from_access_token_param, :from_bearer_param, :from_cookie

  # Admin authenticator - quem pode gerenciar OAuth apps
  admin_authenticator do |_routes|
    frontend_url = ENV.fetch('FRONTEND_URL', 'http://localhost:5173')
    current_user&.administrator? || redirect_to("#{frontend_url}/auth")
  end

  # Skip authorization for trusted applications
  skip_authorization do |_resource_owner, client|
    client.application.trusted?
  end
end
# rubocop:enable Metrics/BlockLength

# Configuration Token
Doorkeeper::JWT.configure do
  secret_key ENV.fetch("DOORKEEPER_JWT_SECRET_KEY")

  signing_method ENV.fetch('DOORKEEPER_JWT_ALGORITHM', 'hs256')

  # Payload
  token_payload do |opts|
    resource_owner_id = opts[:resource_owner_id]
    user = resource_owner_id ? User.find_by(id: resource_owner_id) : nil
    
    if user
      {
        iss: ENV.fetch("DOORKEEPER_JWT_ISS", "evo-auth-service"),
        aud: ENV.fetch("DOORKEEPER_JWT_AUD", '[]'),
        jti: SecureRandom.uuid,
        iat: Time.current.utc.to_i,
        exp: opts[:expires_in].seconds.from_now.to_i,
        sub: user.id.to_s,
        email: user.email,
        name: user.name,
        type: user.type,
        role: user.role_data,
        setup_active: Licensing::Runtime.context&.active? || false
      }
    else
      {
        iss: ENV.fetch("DOORKEEPER_JWT_ISS", "evo-auth-service"),
        aud: ENV.fetch("DOORKEEPER_JWT_AUD", '[]'),
        jti: SecureRandom.uuid,
        iat: Time.current.utc.to_i,
        exp: opts[:expires_in].seconds.from_now.to_i,
        setup_active: Licensing::Runtime.context&.active? || false
      }
    end
  end
end
