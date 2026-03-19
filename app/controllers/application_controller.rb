class ApplicationController < ActionController::Base
  skip_before_action :verify_authenticity_token

  private

  def current_user
    @current_user
  end

  def authenticate_user!
    # Override in subclasses
    head :unauthorized unless current_user
  end

  def verify_authenticity_token
    # Skip for API-only app
  end
end
