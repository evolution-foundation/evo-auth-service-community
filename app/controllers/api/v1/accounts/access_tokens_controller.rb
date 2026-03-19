class Api::V1::Accounts::AccessTokensController < Api::V1::Accounts::BaseController
  before_action :set_owner_context
  before_action :set_access_token, only: [:show, :update, :destroy, :update_token]
  before_action :check_authorization

  # Define o owner_type específico para este controller
  OWNER_TYPE = 'Account'.freeze

  def index
    @access_tokens = @owner.access_tokens.order(:created_at)
    
    apply_pagination
    
    paginated_response(
      data: @access_tokens.map { |token| AccessTokenSerializer.full(token) },
      collection: @access_tokens
    )
  end

  def show
    success_response(data: { access_token: AccessTokenSerializer.full(@access_token) }, message: 'Access token retrieved successfully')
  end

  def create
    # Automatically set issued_id to current user for Account tokens
    token_params = access_token_params.merge(
      owner_type: OWNER_TYPE, 
      owner: @owner,
      issued_id: Current.user&.id
    )
    
    @access_token = AccessToken.new(token_params)

    if @access_token.save
      success_response(data: { access_token: AccessTokenSerializer.full(@access_token) }, message: 'Access token created successfully', status: :created)
    else
      render_unprocessable_entity(@access_token.errors)
    end
  end

  def update
    if @access_token.update(access_token_params)
      success_response(data: { access_token: AccessTokenSerializer.full(@access_token) }, message: 'Access token updated successfully')
    else
      render_unprocessable_entity(@access_token.errors)
    end
  end

  def destroy
    @access_token.destroy
    success_response(data: {}, message: 'Access token deleted successfully')
  end

  def update_token
    if @access_token.update_token
      success_response(
        data: { access_token: AccessTokenSerializer.full(@access_token) },
        message: 'Token regenerated successfully'
      )
    else
      render_unprocessable_entity(@access_token.errors)
    end
  end

  private

  def set_owner_context
    @owner = Current.account
    raise ActiveRecord::RecordNotFound, 'Account not found' unless @owner
  end

  def set_access_token
    @access_token = @owner.access_tokens.find_by!(id: params[:id])
  rescue ActiveRecord::RecordNotFound
    render_not_found('Access token not found')
  end

  def access_token_params
    params.require(:access_token).permit(:name, :scopes, :issued_id)
  end

  def access_token_data(access_token)
    {
      id: access_token.id,
      name: access_token.name,
      token: access_token.token,
      scopes: access_token.scopes,
      owner_type: access_token.owner_type,
      owner_id: access_token.owner_id,
      owner_name: access_token.owner.respond_to?(:name) ? access_token.owner.name : access_token.owner.to_s,
      issued_id: access_token.issued_id,
      issued_by: access_token.issued_by ? { id: access_token.issued_by.id, email: access_token.issued_by.email, name: access_token.issued_by.name } : nil,
      created_at: access_token.created_at,
      updated_at: access_token.updated_at
    }
  end

  # Override check_authorization to use access_tokens resource
  def check_authorization
    # Verificar se usuário tem permissão para gerenciar OAuth applications
    action_map = {
      'index' => 'access_tokens.read',
      'show' => 'access_tokens.read',
      'create' => 'access_tokens.create',
      'update' => 'access_tokens.update',
      'destroy' => 'access_tokens.delete',
      'update_token' => 'access_tokens.update_token'
    }
    
    required_permission = action_map[action_name]
    if required_permission
      resource_key, action_key = required_permission.split('.')
      authorize_resource!(resource_key, action_key)
    else
      true # Para ações não mapeadas, permitir por enquanto
    end
  end
end
