# frozen_string_literal: true

module Licensing
  class SetupGate
    BYPASS_PREFIXES = %w[/setup /rails /auth /api/v1/auth /health].freeze

    UNAVAILABLE_BODY = ['{"error":"service not activated","code":"SETUP_REQUIRED"}'].freeze

    def initialize(app)
      @app = app
    end

    def call(env)
      return @app.call(env) if _fna(env['PATH_INFO'])

      ctx = Runtime.context

      if ctx&.active?
        ctx.track_message
        @app.call(env)
      else
        [503, { 'Content-Type' => 'application/json' }, UNAVAILABLE_BODY]
      end
    end

    private

    def _fna(path)
      BYPASS_PREFIXES.any? { |prefix| path.start_with?(prefix) }
    end
  end
end
