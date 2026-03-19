class Api::V1::Accounts::BaseController < Api::BaseController
  before_action :set_current_account

  private

  def set_current_account
    # Single-tenant: resolve account internally
    @account = Account.first

    unless @account
      error_response('NOT_FOUND', 'Account not found', status: :not_found)
      return
    end

    Current.account = @account
  end

  def paginate_instance_variables(page, per_page)
    %w[
      @access_tokens
      @oauth_applications
      @custom_roles
      @users
    ].each do |var_name|
      var = instance_variable_get(var_name)
      next unless var.respond_to?(:page)

      instance_variable_set(var_name, var.page(page).per(per_page))
    end
  end
end
