# frozen_string_literal: true

# Controller concern to exempt sensitive routes from permission checks
module AuthenticationRoutesExemption
  extend ActiveSupport::Concern
  
  # List of specific actions that should be exempt from permission checks
  EXEMPT_ACTIONS = {
    'api/v1/auth' => ['login'],
  }.freeze
  
  # Check if the current route is exempt from permission verification
  def exempt_from_permission_check?
    controller_name = controller_path.downcase
    action_name_downcase = action_name.downcase
    
    # Check if the specific action is in the exempt list
    EXEMPT_ACTIONS.key?(controller_name) && EXEMPT_ACTIONS[controller_name].include?(action_name_downcase)
  end
  
  # Wrapper for authorize_resource! that checks if the route is exempt
  def authorize_resource_with_exemption!(resource, action, message = nil)
    # If the route is exempt, return true without checking permission
    return true if exempt_from_permission_check?

    # Otherwise, call the original method
    authorize_resource!(resource, action, message)
  end
  
  # Wrapper for authorize_role! that checks if the route is exempt
  def authorize_role_with_exemption!(role_key, message = nil)
    # If the route is exempt, return true without checking permission
    return true if exempt_from_permission_check?
    
    # Otherwise, call the original method
    authorize_role!(role_key, message)
  end
end
