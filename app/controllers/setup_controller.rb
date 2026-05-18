# frozen_string_literal: true

# HTTP endpoints for setup management.
# All /setup/* paths bypass SetupGate, so these actions are
# reachable even when the license is inactive — necessary for the initial
# registration flow.
class SetupController < ActionController::Base
  skip_forgery_protection

  # GET /setup/status
  # Returns current license state and masked api_key when active.
  # Reports 'inactive' whenever no admin user exists so a DB wipe or
  # partial-bootstrap install always lands the user on /setup, even if
  # licensing state disagrees.
  def status
    ctx = Licensing::Runtime.context

    unless ctx
      render json: { status: 'inactive', instance_id: nil }
      return
    end

    # `status` drives the frontend's Setup wizard routing: it must reflect
    # whether the *instance is bootstrapped*, not whether the licensing
    # handshake succeeded. A licensing outage cannot trap users on /setup.
    # The separate `licensed` field exposes the license state for any UI
    # that wants to surface it.
    #
    # Workers can activate the license in a different process (SetupJob);
    # rehydrate from runtime_configs so the web process sees the new state
    # without needing a restart.
    Licensing::Runtime.rehydrate_if_inactive

    bootstrapped = User.exists?
    licensed     = ctx.active?

    resp = {
      status:      bootstrapped ? 'active' : 'inactive',
      licensed:    licensed,
      instance_id: resolve_instance_id(ctx)
    }

    if licensed
      key = ctx.api_key
      resp[:api_key] = "#{key[0..7]}...#{key[-4..]}" if key.present?
    end

    render json: resp
  end

  # GET /setup/register?redirect_uri=<url>
  # Initiates registration with the licensing server.
  # Returns { status: 'pending', register_url: '...' } on success.
  def register
    ctx = Licensing::Runtime.context

    unless ctx
      render json: { error: 'Setup not initialized' }, status: :service_unavailable
      return
    end

    if ctx.active?
      render json: { status: 'active', message: 'Setup is already active' }
      return
    end

    existing_url = ctx.reg_url
    if existing_url.present?
      render json: { status: 'pending', register_url: existing_url }
      return
    end

    begin
      result = Licensing::Registration.init_register(
        instance_id:  resolve_instance_id(ctx),
        tier:         ctx.tier,
        version:      ctx.version,
        redirect_uri: params[:redirect_uri]
      )

      ctx.reg_url   = result['register_url']
      ctx.reg_token = result['token']

      render json: { status: 'pending', register_url: result['register_url'] }
    rescue Licensing::Transport::NetworkError, Licensing::Transport::ResponseError => e
      # Fail open: a licensing outage must never block the installation.
      # The frontend can prossegue e o heartbeat tenta reativar depois.
      Rails.logger.warn "[Setup] Registration unreachable: #{e.message}"
      render json: { status: 'degraded', message: 'Licensing server temporarily unreachable — continuing without activation' }
    end
  end

  # GET /setup/activate?code=XXX
  # Exchanges the authorization code for an api_key, persists the license,
  # and activates the runtime context.
  def activate
    ctx = Licensing::Runtime.context

    unless ctx
      render json: { error: 'Setup not initialized' }, status: :service_unavailable
      return
    end

    if ctx.active?
      render json: { status: 'active', message: 'Setup is already active' }
      return
    end

    code = params[:code]
    if code.blank?
      render json: { error: 'Missing code parameter' }, status: :bad_request
      return
    end

    begin
      result = Licensing::Registration.exchange_code(
        code:        code,
        instance_id: ctx.instance_id
      )

      api_key = result['api_key']
      if api_key.blank?
        render json: { error: 'Invalid or expired code' }, status: :bad_request
        return
      end

      tier        = result['tier'] || ctx.tier
      customer_id = result['customer_id']

      instance_id = resolve_instance_id(ctx)
      Licensing::Store.new.save_runtime_data(api_key: api_key, tier: tier, customer_id: customer_id)
      ctx.activate!(api_key: api_key, instance_id: instance_id)
      ctx.reg_url   = nil
      ctx.reg_token = nil

      Licensing::HeartbeatJob.set(wait: Licensing::Heartbeat::INTERVAL).perform_later

      enqueue_pending_onboarding_pushes

      render json: { status: 'active', message: 'Setup activated successfully!' }
    rescue Licensing::Transport::NetworkError, Licensing::Transport::ResponseError => e
      # Fail open: licensing outage must not trap the user on the activation step.
      # The heartbeat retry path will reactivate once the server is reachable.
      Rails.logger.warn "[Setup] Activation unreachable: #{e.message}"
      render json: { status: 'degraded', message: 'Licensing server temporarily unreachable — continuing without activation' }
    end
  end

  # POST /setup/bootstrap
  # Creates the first admin user, account, RBAC roles, and OAuth app.
  # Only works when the database has no users (fresh installation).
  def bootstrap
    bp = bootstrap_params

    if bp[:password] != bp[:password_confirmation]
      render json: { error: 'Password confirmation does not match' }, status: :unprocessable_entity
      return
    end

    result = SetupBootstrapService.call(
      first_name: bp[:first_name],
      last_name:  bp[:last_name],
      email:      bp[:email],
      password:   bp[:password],
      client_ip:  request.remote_ip
    )

    render json: { status: 'ok', message: 'Installation completed successfully', survey_token: result[:survey_token] }, status: :created

  rescue SetupBootstrapService::AlreadyBootstrappedError => e
    render json: { error: e.message }, status: :conflict

  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /setup/survey
  # Saves onboarding survey answers for the initial admin user.
  # Authenticated via a one-time survey_token generated during bootstrap (TTL: 10 min).
  # If the token has expired, the frontend falls back to the authenticated endpoint
  # (POST /api/v1/setup_survey) after the user logs in.
  def survey
    token   = request.headers['X-Survey-Token'].to_s.strip
    user_id = redis_client.get("survey_token:#{token}")

    if user_id.blank?
      render json: { error: 'Invalid or expired survey token' }, status: :unauthorized
      return
    end

    user = User.find_by(id: user_id)
    unless user
      render json: { error: 'User not found' }, status: :not_found
      return
    end

    survey = user.setup_survey_response || user.build_setup_survey_response
    survey.assign_attributes(survey_params)

    if survey.save
      redis_client.del("survey_token:#{token}")
      Licensing::PushOnboardingSurveyJob.perform_later(survey.id)
      render json: { status: 'ok' }, status: :ok
    else
      render json: { error: survey.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end
  end

  private

  # Scans for setup_survey_responses that have not yet been pushed to the
  # licensing server and enqueues a job for each. Called right after activation
  # so a survey saved before the license became active still gets through.
  def enqueue_pending_onboarding_pushes
    SetupSurveyResponse.where(onboarding_pushed_at: nil).find_each do |survey|
      Licensing::PushOnboardingSurveyJob.perform_later(survey.id)
    end
  end

  def bootstrap_params
    params.permit(:first_name, :last_name, :email, :password, :password_confirmation)
  end

  def survey_params
    params.permit(:team_size, :daily_volume, :main_channel, :main_channel_other,
                  :uses_ai, :biggest_pain, :crm_experience, :main_goal)
  end

  def redis_client
    Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/1'))
  end

  def resolve_instance_id(ctx)
    ctx.instance_id.presence || Licensing::Store.new.load_or_create_instance_id
  end
end
