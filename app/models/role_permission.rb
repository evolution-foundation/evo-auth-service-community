# == Schema Information
#
# Table name: role_permissions
#
#  id         :uuid             not null, primary key
#  role_id    :uuid             not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#

class RolePermission < ApplicationRecord
  # Associations
  belongs_to :role
  has_many :role_permissions_actions, dependent: :destroy
  
  # Validations
  validates :role_id, presence: true
  validates :role_id, uniqueness: true # One permission record per role, can have multiple actions
  
  # Scopes
  scope :for_role, ->(role) { where(role: role) }
  scope :with_actions, -> { includes(:role_permissions_actions) }
  
  # Instance methods
  def permission_keys_list
    role_permissions_actions.pluck(:permission_key)
  end
  
  # Get all resources covered by this permission
  def resources_list
    permission_keys_list.map { |key| key.split('.').first }.uniq.sort
  end
  
  # Get all actions covered by this permission  
  def actions_list
    permission_keys_list.map { |key| key.split('.').last }.uniq.sort
  end
  
  def has_permission?(permission_key)
    role_permissions_actions.exists?(permission_key: permission_key)
  end
  
  def has_resource_action?(resource, action)
    permission_key = "#{resource}.#{action}"
    has_permission?(permission_key)
  end
  
  def add_permission(permission_key)
    return false unless ResourceActionsConfig.valid_permission?(permission_key)
    return false if has_permission?(permission_key)
    
    role_permissions_actions.create!(permission_key: permission_key)
    true
  end
  
  def remove_permission(permission_key)
    role_permissions_actions.where(permission_key: permission_key).destroy_all
  end
  
  def assign_permissions(permission_keys)
    RolePermissionsAction.bulk_create_for_permission(self, permission_keys)
  end
  
  # Get permissions organized by resource
  def permissions_by_resource
    permissions = {}
    
    permission_keys_list.each do |permission_key|
      resource, action = permission_key.split('.')
      permissions[resource] ||= []
      permissions[resource] << action
    end
    
    permissions
  end
  
  # Get detailed permission information with configuration data
  def detailed_permissions
    permission_keys_list.map do |permission_key|
      resource, action = permission_key.split('.')
      
      {
        key: permission_key,
        resource: resource,
        action: action,
        display_name: ResourceActionsConfig.permission_display_name(permission_key),
        resource_config: ResourceActionsConfig.resource(resource),
        action_config: ResourceActionsConfig.action(resource, action)
      }
    end
  end
  
  # For backward compatibility - returns actions as hash
  def actions
    permissions_by_resource.transform_values do |actions|
      actions.each_with_object({}) { |action, hash| hash[action] = true }
    end
  end
end