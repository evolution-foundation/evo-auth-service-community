# frozen_string_literal: true

module HealthSerializer
  extend self

  def full(status:, database:, redis:, version:)
    {
      status: status,
      database: database,
      redis: redis,
      version: version,
      timestamp: Time.current.iso8601
    }
  end
end
