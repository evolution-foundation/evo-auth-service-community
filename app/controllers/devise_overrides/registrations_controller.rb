class DeviseOverrides::RegistrationsController < DeviseTokenAuth::RegistrationsController
  def create
    # Check if account signup is enabled
    unless Rails.application.config.enable_account_signup
      return render json: {
        status: 'error',
        errors: ['Account registration is currently disabled']
      }, status: :forbidden
    end

    build_resource

    unless @resource.present?
      raise DeviseTokenAuth::Errors::NoResourceDefinedError,
            "#{controller_name.classify} resource is not defined"
    end

    # give redirect value from params priority
    @redirect_url = params[:confirm_success_url]

    # fall back to default value if provided
    @redirect_url ||= DeviseTokenAuth.default_confirm_success_url

    # success redirect url is required
    if confirmable_enabled? && !@redirect_url
      return render_create_error_missing_confirm_success_url
    end

    # if whitelist is set, validate redirect_url against whitelist
    if DeviseTokenAuth.redirect_whitelist
      unless DeviseTokenAuth::Url.whitelisted?(@redirect_url)
        return render_create_error_redirect_url_not_allowed
      end
    end

    begin
      # override email confirmation, must be sent manually from ctrl
      resource_class.set_callback('create', :after, :send_on_create_confirmation_instructions)
      resource_class.skip_callback('create', :after, :send_on_create_confirmation_instructions)

      if @resource.respond_to? :skip_confirmation_notification!
        # Fix duplicate e-mails by disabling Devise confirmation e-mail
        @resource.skip_confirmation_notification!
      end

      if @resource.save
        yield @resource if block_given?

        unless @resource.confirmed?
          # user will require email authentication
          @resource.send_confirmation_instructions({
            client_config: params[:config_name],
            redirect_url: @redirect_url
          })
        else
          # email auth has been bypassed, authenticate user
          @token = @resource.create_token
          @resource.save!
          update_auth_header
        end

        render_create_success
      else
        clean_up_passwords @resource
        render_create_error
      end
    rescue ActiveRecord::RecordNotUnique
      clean_up_passwords @resource
      render_create_error_email_already_exists
    end
  end

  private

  def render_create_success
    render json: {
      status: 'success',
      data: resource_data(resource_json: @resource.as_json(except: [
        :tokens, :created_at, :updated_at
      ]))
    }
  end

  def render_create_error
    render json: {
      status: 'error',
      data: @resource,
      errors: resource_errors
    }, status: :unprocessable_entity
  end

  def render_create_error_missing_confirm_success_url
    render json: {
      status: 'error',
      data: @resource,
      errors: [I18n.t('devise_token_auth.registrations.missing_confirm_success_url')]
    }, status: :unprocessable_entity
  end

  def render_create_error_redirect_url_not_allowed
    render json: {
      status: 'error',
      data: @resource,
      errors: [I18n.t('devise_token_auth.registrations.redirect_url_not_allowed', redirect_url: @redirect_url)]
    }, status: :unprocessable_entity
  end

  def render_create_error_email_already_exists
    render json: {
      status: 'error',
      data: @resource,
      errors: [I18n.t('devise_token_auth.registrations.email_already_exists')]
    }, status: :unprocessable_entity
  end

  def resource_errors
    return @resource.errors.to_hash.merge(full_messages: @resource.errors.full_messages) if @resource.errors.respond_to?(:to_hash)

    @resource.errors
  end
end
