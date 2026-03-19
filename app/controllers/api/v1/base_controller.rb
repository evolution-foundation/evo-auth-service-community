class Api::V1::BaseController < Api::BaseController
  private

  def paginate_instance_variables(page, per_page)
    %w[
      @users
      @plans
      @oauth_applications
    ].each do |var_name|
      var = instance_variable_get(var_name)
      next unless var.respond_to?(:page)

      instance_variable_set(var_name, var.page(page).per(per_page))
    end
  end
end
