# OpenTelemetry configuration for Tempo tracing
if ENV['OTEL_TRACES_ENABLED'] == 'true'
  require 'opentelemetry/sdk'
  require 'opentelemetry/exporter/otlp'
  require 'opentelemetry/instrumentation/all'

  OpenTelemetry::SDK.configure do |c|
    c.service_name = ENV.fetch('OTEL_SERVICE_NAME', 'evo-auth-service')
    c.use_all # Automatically instrument all available libraries
  end

  Rails.logger.info "OpenTelemetry tracing initialized for Tempo: #{ENV['OTEL_EXPORTER_OTLP_ENDPOINT']}"
else
  Rails.logger.info 'OpenTelemetry tracing is disabled (OTEL_TRACES_ENABLED != true)'
end
