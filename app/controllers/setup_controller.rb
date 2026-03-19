# frozen_string_literal: true

# HTTP endpoints for setup management.
# All /setup/* paths bypass SetupGate, so these actions are
# reachable even when the license is inactive — necessary for the initial
# registration flow.
class SetupController < ActionController::Base
  # GET /setup/status
  # Returns current license state and masked api_key when active.
  def status
    ctx = Licensing::Runtime.context

    unless ctx
      render json: { status: 'inactive', instance_id: nil }
      return
    end

    resp = {
      status:      ctx.active? ? 'active' : 'inactive',
      instance_id: resolve_instance_id(ctx)
    }

    if ctx.active?
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
      render json: { error: 'Failed to contact licensing server', details: e.message },
             status: :bad_gateway
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

      render json: { status: 'active', message: 'Setup activated successfully!' }
    rescue Licensing::Transport::NetworkError, Licensing::Transport::ResponseError => e
      render json: { error: 'Failed to contact licensing server', details: e.message },
             status: :bad_gateway
    end
  end

  private

  def resolve_instance_id(ctx)
    ctx.instance_id.presence || Licensing::Store.new.load_or_create_instance_id
  end
end
