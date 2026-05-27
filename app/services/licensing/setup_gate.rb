# frozen_string_literal: true

module Licensing
  # Best-effort licensing observability — never blocks requests.
  #
  # Previous behaviour returned 503 SETUP_REQUIRED for every non-bypassed
  # request whenever Runtime.context wasn't active. That meant a transient
  # registration failure (licensing server unreachable on first boot)
  # permanently bricked the entire CRM API surface for self-hosted users:
  # login worked (bypassed) but /api/v1/account, /api/v1/permissions,
  # /api/v1/users/:id/check_permission, etc. all returned 503 forever.
  #
  # New behaviour: try to rehydrate the context from runtime_configs if
  # inactive (cheap, non-blocking — already used by Licensing::Runtime),
  # track the message if active, then always forward the request.
  # Licensing failure is an observability concern, not an authorization
  # gate. Self-hosted installs must keep working even when the licensing
  # server is unreachable.
  class SetupGate
    def initialize(app)
      @app = app
    end

    def call(env)
      ctx = Runtime.context
      Runtime.rehydrate_if_inactive if ctx && !ctx.active?
      ctx.track_message if ctx&.active?
      @app.call(env)
    end
  end
end
