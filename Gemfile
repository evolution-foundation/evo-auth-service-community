source "https://rubygems.org"

ruby '3.4.4'

# Rails Framework - matching Evolution version
gem "rails", "~> 7.1"
# Use postgresql as the database for Active Record
gem "pg"
# Use the Puma web server
gem "puma"

##--- gems for authentication & authorization ---##
gem 'devise', '>= 4.9.4'
gem 'devise-secure_password', git: 'https://github.com/chatwoot/devise-secure_password', branch: 'chatwoot'
gem 'devise_token_auth', '>= 1.2.3'

# authorization
gem "jwt"
gem "pundit"
gem "flag_shih_tzu"

# worked with microsoft refresh token
gem 'omniauth-oauth2'

# need for google auth
gem 'omniauth', '>= 2.1.2'
gem 'omniauth-google-oauth2', '>= 1.1.3'
gem 'omniauth-rails_csrf_protection', '~> 1.0', '>= 1.0.2'

# OAuth Provider
gem 'doorkeeper', '~> 5.8'
gem 'doorkeeper-jwt'

# Multi-Factor Authentication - matching Evolution versions
gem "rotp", "~> 6.3"
gem "rqrcode", "~> 2.2"

# Background Jobs - matching Evolution versions
gem "sidekiq", ">= 7.3.1"
gem "redis"
gem "redis-namespace"

# Prometheus Metrics
gem "prometheus-client"

# Cloud Storage (S3-compatible: AWS, Backblaze B2, Cloudflare R2, Minio)
gem "aws-sdk-s3", require: false

# API & Serialization
gem "rack-cors", "2.0.0", require: "rack/cors"
gem "kaminari"
gem "oj", "~> 3.16"

# Validation & Utilities
gem "valid_email2"
gem "telephone_number"
gem "attr_extras"

# Configuration
gem "dotenv-rails", ">= 3.0.0"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Bootsnap for faster boot times
gem "bootsnap", require: false

# Required for Ruby 3.4+ compatibility
gem "ostruct"

# Algorithm for hashing passwords
gem 'argon2'

# Symmetric encryption for shared config secrets
gem 'fernet'

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false

  # Testing framework
  gem "rspec-rails", "~> 6.1"
  gem "factory_bot_rails", "~> 6.4"
  gem "faker", "~> 3.2"
  
end

group :test do
  # Test coverage
  gem "simplecov", "~> 0.22", require: false
  gem "simplecov-lcov", "~> 0.8", require: false
  
  # Testing utilities
  gem "shoulda-matchers", "~> 6.0"
  gem "database_cleaner-active_record", "~> 2.1"
  gem "webmock", "~> 3.19"
  gem "vcr", "~> 6.2"
  gem "timecop", "~> 0.9"
  
  # Request testing
  gem "rack-test", "~> 2.1"
  gem "json_spec", "~> 1.1"
end

group :development do
  # Preview emails in the browser instead of sending them
  gem "letter_opener"
end

gem "opentelemetry-sdk", "~> 1.10"
gem "opentelemetry-exporter-otlp", "~> 0.31.1"
gem "opentelemetry-instrumentation-all", "~> 0.90.1"
