require_relative "boot"

# Licensing middleware must be required explicitly so the constant is available
# when config.middleware.use is evaluated inside the Application class body
# (Zeitwerk autoloading is not active at that point in the boot sequence).
require_relative "../app/services/licensing/setup_gate"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module EvoAuthService
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true

    # Configure UUID as default primary key type
    config.generators do |g|
      g.orm :active_record, primary_key_type: :uuid
    end

    # Enable sessions for OAuth and API authentication
    config.middleware.use ActionDispatch::Cookies
    config.middleware.use ActionDispatch::Session::CookieStore

    # Licensing gate — gates all non-bypass requests behind license validation.
    config.middleware.use Licensing::SetupGate

    # I18n configuration - Multi-language support
    config.i18n.default_locale = :en
    config.i18n.available_locales = [:en, :es, :fr, :it, :pt, :'pt-BR']
    config.i18n.fallbacks = [:en]
    # Raise error if translation is missing in development/test
    config.i18n.raise_on_missing_translations = Rails.env.development? || Rails.env.test?

    # Host authorization - Allow specific hosts
    config.hosts << "api.evoai.app"
    config.hosts << "api.staging.evoai.app"
    config.hosts << /.*\.evoai\.app/     # Allow all evoai.app subdomains
    config.hosts << "localhost"
    
    # Allow hosts from CORS_ORIGINS (extract hostnames from URLs)
    if ENV['CORS_ORIGINS'].present?
      ENV['CORS_ORIGINS'].split(',').each do |origin|
        host = URI.parse(origin.strip).host rescue nil
        config.hosts << host if host.present?
      end
    end
  end
end
