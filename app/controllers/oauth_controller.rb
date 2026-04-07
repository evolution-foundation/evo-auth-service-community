class OauthController < ApplicationController
  include Doorkeeper::Rails::Helpers
  before_action :doorkeeper_authorize!, only: [:token_info]

  def callback
    # Callback para aplicações OAuth após autorização
    if params[:error]
      render_oauth_error
    elsif params[:code]
      render_oauth_success
    else
      render_oauth_fallback
    end
  end

  def accounts
    account = RuntimeConfig.account
    return render json: [] unless account

    render json: [{ id: account['id'], name: account['name'] }]
  end

  # RFC 7591 - Dynamic Client Registration
  def register
    begin
      registration_data = params.permit(
        :client_name,
        :client_id,
        :client_secret,
        :scope,
        :token_endpoint_auth_method,
        redirect_uris: [],
        grant_types: [],
        response_types: []
      )

      # Validações básicas
      if registration_data[:client_name].blank?
        return render json: {
          error: 'invalid_client_metadata',
          error_description: 'client_name is required'
        }, status: :bad_request
      end

      # Gerar client_id se não fornecido
      client_id = registration_data[:client_id].presence || SecureRandom.uuid

      # Gerar client_secret se não fornecido
      client_secret = registration_data[:client_secret].presence || Doorkeeper::OAuth::Helpers::UniqueToken.generate

      # Verificar se client_id já existe
      if OauthApplication.find_by(uid: client_id)
        return render json: {
          error: 'invalid_client_metadata',
          error_description: 'client_id already exists'
        }, status: :bad_request
      end

      # Configurações padrão
      redirect_uris = registration_data[:redirect_uris] || []
      grant_types = registration_data[:grant_types] || ['authorization_code', 'refresh_token']
      response_types = registration_data[:response_types] || ['code']
      scopes = registration_data[:scope] || 'read'

      # Criar aplicação OAuth
      application = OauthApplication.create!(
        name: registration_data[:client_name],
        uid: client_id,
        secret: client_secret,
        redirect_uri: redirect_uris.join(' '),
        scopes: scopes,
        confidential: false # RFC 7591 apps são públicas por padrão
      )

      render json: {
        client_id: application.uid,
        client_secret: application.secret,
        client_name: application.name,
        redirect_uris: redirect_uris,
        grant_types: grant_types,
        response_types: response_types,
        scope: application.scopes
      }, status: :created

    rescue StandardError => e
      Rails.logger.error "OAuth Registration Error: #{e.message}"
      render json: {
        error: 'server_error',
        error_description: 'Internal server error'
      }, status: :internal_server_error
    end
  end

  def token_info
    render json: {
      resource_owner_id: doorkeeper_token.resource_owner_id,
      scopes: doorkeeper_token.scopes,
      expires_in: doorkeeper_token.expires_in_seconds,
      application: {
        uid: doorkeeper_token.application.uid,
        name: doorkeeper_token.application.name
      }
    }
  end

  # RFC 8414 - OAuth 2.0 Authorization Server Metadata
  def oauth_metadata
    backend_url = request.base_url
    frontend_url = ENV.fetch('FRONTEND_URL', 'http://localhost:5173')

    render json: {
      issuer: backend_url,
      authorization_endpoint: "#{backend_url}/oauth/authorize",
      token_endpoint: "#{backend_url}/oauth/token",
      registration_endpoint: "#{backend_url}/oauth/register",
      revocation_endpoint: "#{backend_url}/oauth/revoke",
      introspection_endpoint: "#{backend_url}/oauth/introspect",
      userinfo_endpoint: "#{backend_url}/oauth/token_info",
      response_types_supported: ['code'],
      grant_types_supported: ['authorization_code', 'client_credentials', 'password', 'refresh_token'],
      scopes_supported: doorkeeper_scopes,
      token_endpoint_auth_methods_supported: ['client_secret_post', 'client_secret_basic'],
      code_challenge_methods_supported: ['S256'],
      service_documentation: "#{backend_url}/docs/oauth-provider-guide",
      ui_locales_supported: ['en', 'pt-BR', 'es'],
      op_policy_uri: "#{frontend_url}/privacy",
      op_tos_uri: "#{frontend_url}/terms",
      evolution_extensions: {
        dynamic_oauth_available: true,
        dynamic_client_format: 'dynamic_client_{client_id}',
        available_accounts_endpoint: "#{backend_url}/api/v1/dynamic_oauth/available_accounts",
        validate_client_endpoint: "#{backend_url}/api/v1/dynamic_oauth/validate_client",
        api_base_url: "#{backend_url}/api/v1",
        frontend_base_url: frontend_url,
        authorization_ui: "#{frontend_url}/auth",
        oauth_callback_ui: "#{frontend_url}/oauth/callback"
      }
    }
  end

  # RFC 8707 - OAuth 2.0 Resource Registration
  def oauth_protected_resource
    backend_url = request.base_url

    render json: {
      resource: backend_url,
      authorization_servers: [backend_url],
      scopes_supported: doorkeeper_scopes,
      bearer_methods_supported: ['header', 'query'],
      resource_documentation: "#{backend_url}/api/docs",
      protected_resources: [
        {
          resource: "#{backend_url}/api/v1",
          scopes: doorkeeper_scopes,
          description: "Evo Auth Service API"
        },
        {
          resource: "#{backend_url}/mcp",
          scopes: doorkeeper_scopes,
          description: "MCP Server Endpoints",
          bearer_methods_supported: ['header', 'query']
        }
      ],
      evolution_extensions: {
        api_base_url: "#{backend_url}/api/v1",
        mcp_endpoint: "#{backend_url}/mcp/sse",
        mcp_transport: 'sse',
        mcp_version: '1.0.0',
        mcp_authentication_note: "For SSE connections, use ?access_token=<token> query parameter if Authorization header is not supported by proxy"
      }
    }
  end

  private

  def render_oauth_error
    render json: {
      error: params[:error],
      error_description: params[:error_description]
    }, status: :bad_request
  end

  def render_oauth_success
    render json: {
      code: params[:code],
      state: params[:state]
    }
  end

  def render_oauth_fallback
    render json: {
      message: 'OAuth callback received',
      params: params.except(:controller, :action)
    }
  end

  private

  def doorkeeper_scopes
    Doorkeeper.configuration.scopes.all.map(&:to_s)
  end
end
