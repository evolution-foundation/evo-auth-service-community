# Features/FeatureTypes removed in community edition — endpoints return empty data
class Api::V1::FeaturesController < Api::BaseController
  before_action :check_authorization

  # GET /api/v1/features
  def index
    success_response(
      data: [],
      message: 'Features retrieved successfully'
    )
  end

  # GET /api/v1/features/:id
  def show
    error_response('NOT_FOUND', 'Feature not found', status: :not_found)
  end

  # GET /api/v1/features/types
  def types
    success_response(
      data: [],
      message: 'Feature types retrieved successfully'
    )
  end

  private

  def check_authorization
    action_map = {
      'index' => 'features.read',
      'show' => 'features.read',
      'types' => 'features.read'
    }

    required_permission = action_map[action_name]
    if required_permission
      resource_key, action_key = required_permission.split('.')
      authorize_resource!(resource_key, action_key)
    else
      Rails.logger.debug "Action '#{action_name}' not mapped to any permission in #{self.class.name}"
      true
    end
  end
end
