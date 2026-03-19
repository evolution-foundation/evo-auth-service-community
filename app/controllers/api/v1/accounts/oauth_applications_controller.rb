class Api::V1::Accounts::OauthApplicationsController < Api::V1::Accounts::BaseController
  before_action :set_oauth_application, only: [:show, :update, :destroy, :regenerate_secret]
  before_action :check_authorization

  def index
    @oauth_applications = Current.account.oauth_applications.order(:created_at)
    
    apply_pagination
    
    paginated_response(
      data: @oauth_applications.map { |app| OauthApplicationSerializer.basic(app) },
      collection: @oauth_applications
    )
  end

  def show
    success_response(data: { oauth_application: OauthApplicationSerializer.basic(@oauth_application) }, message: 'OAuth application retrieved successfully')
  end

  def create
    @oauth_application = Current.account.oauth_applications.build(oauth_application_params)

    if @oauth_application.save
      success_response(data: { oauth_application: OauthApplicationSerializer.basic(@oauth_application) }, message: 'OAuth application created successfully', status: :created)
    else
      render_unprocessable_entity(@oauth_application.errors)
    end
  end

  def update
    if @oauth_application.update(oauth_application_params)
      success_response(data: { oauth_application: OauthApplicationSerializer.basic(@oauth_application) }, message: 'OAuth application updated successfully')
    else
      render_unprocessable_entity(@oauth_application.errors)
    end
  end

  def destroy
    @oauth_application.destroy
    success_response(data: {}, message: 'OAuth application deleted successfully')
  end

  def regenerate_secret
    @oauth_application.update!(secret: Doorkeeper::OAuth::Helpers::UniqueToken.generate)
    success_response(
      data: { oauth_application: OauthApplicationSerializer.basic(@oauth_application) },
      message: 'Secret regenerated successfully'
    )
  end

  private

  def set_oauth_application
    @oauth_application = Current.account.oauth_applications.find_by!(id: params[:id])
  rescue ActiveRecord::RecordNotFound
    render_not_found('OAuth application not found')
  end

  def oauth_application_params
    params.require(:oauth_application).permit(:name, :redirect_uri, :scopes, :confidential, :trusted)
  end

  def oauth_application_data(app)
    {
      id: app.id,
      name: app.name,
      uid: app.uid,
      secret: app.display_secret,
      redirect_uri: app.redirect_uri,
      scopes: app.scopes,
      confidential: app.confidential,
      trusted: app.trusted,
      account_id: app.account_id,
      created_at: app.created_at,
      updated_at: app.updated_at
    }
  end

  def check_authorization
    # Verificar se usuário tem permissão para gerenciar OAuth applications
    action_map = {
      'index' => 'oauth_applications.read',
      'show' => 'oauth_applications.read',
      'create' => 'oauth_applications.create',
      'update' => 'oauth_applications.update',
      'destroy' => 'oauth_applications.delete',
      'regenerate_secret' => 'oauth_applications.regenerate_secret'
    }
    
    required_permission = action_map[action_name]
    if required_permission
      resource_key, action_key = required_permission.split('.')
      authorize_resource!(resource_key, action_key)
    else
      true # Para ações não mapeadas, permitir por enquanto
    end
  end

  def doorkeeper_scopes
    Doorkeeper.configuration.scopes.all.map(&:to_s)
  end
end
