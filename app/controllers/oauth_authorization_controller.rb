class OauthAuthorizationController < Doorkeeper::AuthorizationsController
  before_action :authenticate_user!

  private

  def authenticate_user!
    # Use Devise authentication
    redirect_to new_user_session_path unless user_signed_in?
  end

  def current_resource_owner
    current_user if user_signed_in?
  end
end
