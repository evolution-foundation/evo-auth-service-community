# Plans removed in community edition — endpoints return empty data
class Api::V1::PlansController < Api::BaseController
  before_action :check_authorization

  # GET /api/v1/plans
  def index
    success_response(
      data: [],
      message: 'Plans retrieved successfully'
    )
  end

  # GET /api/v1/plans/:id
  def show
    error_response('NOT_FOUND', 'Plan not found', status: :not_found)
  end

  private

  def check_authorization
    action_map = {
      'index' => 'plans.read',
      'show' => 'plans.read'
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
