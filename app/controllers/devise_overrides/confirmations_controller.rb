class DeviseOverrides::ConfirmationsController < DeviseTokenAuth::ConfirmationsController
  def show
    @resource = resource_class.confirm_by_token(resource_params[:confirmation_token])

    if @resource.errors.empty?
      yield @resource if block_given?

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
