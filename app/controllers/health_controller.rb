require 'prometheus/client'
require 'prometheus/client/formats/text'

class HealthController < ActionController::Base
  # Prometheus metrics endpoint
  def metrics
    render plain: Prometheus::Client::Formats::Text.marshal(Prometheus::Client.registry),
           content_type: Prometheus::Client::Formats::Text::CONTENT_TYPE
  end

  # Liveness probe - always returns 200 if app process is running
  def show
    # Check database connection
    database_status = check_database_connection

    # Check Redis connection
    redis_status = check_redis_connection

    health_data = {
      status: 'ok',
      timestamp: Time.current.iso8601,
      version: '1.0.0',
      environment: Rails.env,
      services: {
        database: database_status,
        redis: redis_status
      },
      configuration: {
        app_name: Rails.application.config.app_name,
        app_url: Rails.application.config.app_url,
        mfa_enabled: true,
        cors_origins: ENV.fetch('CORS_ORIGINS', '').split(',').size,
        email_provider: get_email_provider_info
      }
    }

    # Always return 200 for liveness - app process is running
    render json: health_data, status: :ok
  end

  # Readiness probe - returns 200 only if dependencies are ready
  def ready
    # Check database connection
    database_status = check_database_connection

    # Check Redis connection
    redis_status = check_redis_connection

    # Overall readiness status
    ready = database_status[:status] == 'ok' && redis_status[:status] == 'ok'

    health_data = {
      status: ready ? 'ready' : 'not_ready',
      timestamp: Time.current.iso8601,
      services: {
        database: database_status,
        redis: redis_status
      }
    }

    status_code = ready ? :ok : :service_unavailable
    render json: health_data, status: status_code
  end

  private

  def check_database_connection
    ActiveRecord::Base.connection.execute('SELECT 1')
    { status: 'ok', message: 'Database connection successful' }
  rescue => e
    { status: 'error', message: "Database connection failed: #{e.message}" }
  end

  def check_redis_connection
    Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/1')).ping
    { status: 'ok', message: 'Redis connection successful' }
  rescue => e
    { status: 'error', message: "Redis connection failed: #{e.message}" }
  end

  def get_email_provider_info
    delivery_method = ActionMailer::Base.delivery_method

    case delivery_method
    when :bms
      {
        provider: 'BMS (Brius Message System)',
        method: 'bms',
        configured: ENV['BMS_API_KEY'].present?,
        ippool: ENV.fetch('BMS_IPPOOL', 'default')
      }
    when :resend
      {
        provider: 'Resend',
        method: 'resend',
        configured: ENV['RESEND_API_KEY'].present?
      }
    when :smtp
      {
        provider: 'SMTP',
        method: 'smtp',
        configured: ENV['SMTP_ADDRESS'].present?,
        address: ENV.fetch('SMTP_ADDRESS', 'localhost'),
        port: ENV.fetch('SMTP_PORT', 587)
      }
    when :letter_opener
      {
        provider: 'Letter Opener (Development)',
        method: 'letter_opener',
        configured: true
      }
    else
      {
        provider: delivery_method.to_s.titleize,
        method: delivery_method.to_s,
        configured: 'unknown'
      }
    end
  end
end
