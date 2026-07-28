class DeviseOverrides::ConfirmationsController < DeviseTokenAuth::ConfirmationsController
  def show
    @resource = resource_class.confirm_by_token(resource_params[:confirmation_token])

    if @resource.errors.empty?
      yield @resource if block_given?

      # The validation cache holds the serialized user for 5 minutes, and that
      # payload carries `confirmed`/`confirmed_at`. Without this, a consumer that
      # validated the token moments before the confirmation keeps reading
      # `confirmed: false` until the entry expires — stale data served as truth,
      # right after the user did the one thing that changes it.
      TokenValidationService.invalidate_cache_for_user(@resource)

      redirect_header_options = { account_confirmation_success: true }
      redirect_headers = build_redirect_headers(redirect_header_options)

      frontend_url = ENV.fetch('FRONTEND_URL', 'http://localhost:5173')
      redirect_to "#{frontend_url}/auth?#{redirect_headers.to_query}", allow_other_host: true
    else
      frontend_url = ENV.fetch('FRONTEND_URL', 'http://localhost:5173')
      redirect_to "#{frontend_url}/auth?account_confirmation_success=false", allow_other_host: true
    end
  end

  private

  def build_redirect_headers(options = {})
    {
      account_confirmation_success: options[:account_confirmation_success] || false,
      config: params[:config]
    }.compact
  end
end
