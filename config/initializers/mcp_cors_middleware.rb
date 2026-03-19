# frozen_string_literal: true

# Middleware específico para adicionar headers CORS máximos para endpoints MCP
class McpCorsMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, response = @app.call(env)

    # Aplicar CORS máximo apenas para rotas MCP
    if env['PATH_INFO']&.start_with?('/mcp')

      # Headers CORS máximos para MCP
      cors_headers = {
        'Access-Control-Allow-Origin' => '*',
        'Access-Control-Allow-Methods' => '*',
        'Access-Control-Allow-Headers' => '*',
        # Cannot use credentials with wildcard origin for security
        'Access-Control-Expose-Headers' => '*',
        'Access-Control-Max-Age' => '86400',
        'Vary' => 'Origin'
      }

      # Handle preflight OPTIONS requests
      if env['REQUEST_METHOD'] == 'OPTIONS'
        return [200, cors_headers.merge('Content-Length' => '0'), ['']]
      end

      # Merge CORS headers with existing response headers
      headers = headers.merge(cors_headers)
    end

    [status, headers, response]
  end
end

# Adicionar o middleware no início da stack para garantir que seja executado
Rails.application.config.middleware.insert_before ActionDispatch::Static, McpCorsMiddleware
