# config/initializers/cors.rb
# ref: https://github.com/cyu/rack-cors

# font cors issue with CDN
# Ref: https://stackoverflow.com/questions/56960709/rails-font-cors-policy
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  # Get CORS origins from environment variable
  # Parse and clean origins (remove whitespace and filter empty strings)
  cors_origins_raw = ENV.fetch('CORS_ORIGINS', 'http://localhost:3000,http://localhost:5173,http://localhost:8080,http://localhost:3001')
  cors_origins = cors_origins_raw.split(',').map(&:strip).reject(&:empty?)
  
  # Log CORS origins for debugging
  Rails.logger.info "CORS Origins configured: #{cors_origins.inspect}"

  allow do
    origins cors_origins

    # Static assets
    resource '/packs/*', headers: :any, methods: [:get, :options]
    resource '/audio/*', headers: :any, methods: [:get, :options]

    # Public API endpoints
    resource '/public/api/*', headers: :any, methods: :any

    # Setup/installation endpoints
    resource '/setup/*',
             headers: :any,
             methods: [:get, :post, :options],
             credentials: false

    # License management endpoints
    resource '/license/*',
             headers: :any,
             methods: [:get, :options],
             credentials: true

    # OAuth authentication endpoints
    resource '/oauth/*',
             headers: :any,
             methods: :any,
             expose: %w[Authorization],
             credentials: true

    # MCP endpoints for tool discovery
    resource '/mcp/*',
             headers: :any,
             methods: :any,
             credentials: false,
             max_age: 86400,
             expose: :any

    # API endpoints in development or when explicitly enabled
    # Parse ENABLE_API_CORS as boolean (handles "true", "false", "1", "0", etc.)
    enable_api_cors_raw = ENV.fetch('ENABLE_API_CORS', 'true').to_s.downcase.strip
    enable_api_cors = %w[true 1 yes on].include?(enable_api_cors_raw)
    is_dev_env = Rails.env.development?
    
    # Log CORS configuration for debugging
    Rails.logger.info "CORS API enabled: #{enable_api_cors}, Rails.env: #{Rails.env}, is_dev: #{is_dev_env}"
    
    if is_dev_env || enable_api_cors
      resource '/api/*',
               headers: :any,
               methods: :any,
               expose: %w[Authorization],
               credentials: true
    end
  end

end

################################################
######### Action Cable Related Config ##########
################################################

# Mount Action Cable outside main process or domain
# Rails.application.config.action_cable.mount_path = nil
# Rails.application.config.action_cable.url = 'wss://example.com/cable'
# Rails.application.config.action_cable.allowed_request_origins = [ 'http://example.com', /http:\/\/example.*/ ]

# To Enable connecting to the API channel public APIs
# ref : https://medium.com/@emikaijuin/connecting-to-action-cable-without-rails-d39a8aaa52d5
Rails.application.config.action_cable.disable_request_forgery_protection = true
