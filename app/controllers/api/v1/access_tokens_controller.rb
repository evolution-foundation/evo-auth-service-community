class Api::V1::AccessTokensController < Api::BaseController
  before_action :set_owner_context
  before_action :set_access_token, only: [:show, :update, :destroy, :update_token]
  before_action :check_authorization

  OWNER_TYPE = 'User'.freeze

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
    token_params = access_token_params.merge(
      owner_type: OWNER_TYPE,
      owner: @owner,
      issued_id: Current.user&.id
    )

    @access_token = AccessToken.new(token_params)

    if @access_token.save
      audit('create')
      success_response(data: { access_token: AccessTokenSerializer.with_token(@access_token) }, message: 'Access token created successfully', status: :created)
    else
      render_unprocessable_entity(@access_token.errors)
    end
  end

  def update
    if @access_token.update(access_token_params)
      # The cached validation carries the scopes; drop it so a narrowed token is
      # narrowed on the next request.
      TokenValidationService.invalidate_cache_for_digest(@access_token.token_digest)
      audit('update')
      success_response(data: { access_token: AccessTokenSerializer.full(@access_token) }, message: 'Access token updated successfully')
    else
      render_unprocessable_entity(@access_token.errors)
    end
  end

  def destroy
    @access_token.destroy
    TokenValidationService.invalidate_cache_for_digest(@access_token.token_digest)
    audit('destroy')
    success_response(data: {}, message: 'Access token deleted successfully')
  end

  def update_token
    if @access_token.update_token
      audit('update_token')
      success_response(
        data: { access_token: AccessTokenSerializer.with_token(@access_token) },
        message: 'Token regenerated successfully'
      )
    else
      render_unprocessable_entity(@access_token.errors)
    end
  end

  private

  # Audit trail: who created, changed, regenerated or deleted which token. The
  # value never goes to the log.
  def audit(action)
    Rails.logger.warn(
      "[AccessTokens##{action}] actor=#{current_user&.id} via=#{@authenticated_access_token ? 'access_token' : 'session'} " \
      "token=#{@access_token.id} owner=#{@access_token.owner_type}:#{@access_token.owner_id} scopes=#{@access_token.scopes}"
    )
  end

  def set_owner_context
    @owner = current_user
  end

  def set_access_token
    @access_token = @owner.access_tokens.find_by!(id: params[:id])
  rescue ActiveRecord::RecordNotFound
    render_not_found('Access token not found')
  end

  def access_token_params
    params.require(:access_token).permit(:name, :scopes, :issued_id)
  end

  def check_authorization
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
      true
    end
  end
end
