class Api::V1::HealthController < ApplicationController
  include ApiResponseHelper

  def show
    success_response(
      data: HealthSerializer.full(
        status: 'ok',
        database: database_status,
        redis: redis_status,
        version: '1.0.0'
      ),
      message: 'Service health check completed successfully'
    )
  end

  private

  def database_status
    ActiveRecord::Base.connection.execute('SELECT 1')
    'connected'
  rescue StandardError
    'disconnected'
  end

  def redis_status
    Redis.new.ping
    'connected'
  rescue StandardError
    'disconnected'
  end
end
