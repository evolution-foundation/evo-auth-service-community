# == Schema Information
#
# Table name: role_permissions_actions
#
#  id              :uuid             not null, primary key
#  role_id         :uuid             not null
#  permission_key  :string(100)      not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#

class RolePermissionsAction < ApplicationRecord
  # Associations
  belongs_to :role
  
  # Validations
  validates :role_id, presence: true
  validates :permission_key, presence: true, length: { maximum: 100 }
  validates :role_id, uniqueness: { scope: :permission_key }
  validate :permission_key_must_be_valid
  
  # Scopes
  scope :for_role, ->(role) { where(role: role) }
  scope :for_permission_key, ->(permission_key) { where(permission_key: permission_key) }
  scope :for_resource, ->(resource) { where("permission_key LIKE ?", "#{resource}.%") }
  scope :for_action, ->(action) { where("permission_key LIKE ?", "%.#{action}") }
  
  # Class methods
  def self.bulk_create_for_role(role, permission_keys)
    return if permission_keys.blank?
    
    # Remove existing associations
    where(role: role).delete_all
    
    # Create new associations
    valid_keys = permission_keys.select { |key| ResourceActionsConfig.valid_permission?(key) }
    
    valid_keys.each do |permission_key|
      create!(
        role: role,
        permission_key: permission_key
      )
    end
  end
  
  def self.permissions_for_role(role)
    where(role: role).pluck(:permission_key).uniq
  end
  
  def self.permissions_for_user_in_account(user, account)
    joins(role: { user_roles: :user })
      .where(user_roles: { user: user, account: account })
      .pluck(:permission_key)
      .uniq
  end
  
  # Instance methods
  def resource
    permission_key.split('.').first if permission_key.present?
  end
  
  def action
    permission_key.split('.').last if permission_key.present?
  end
  
  def action_config
    return nil unless valid_permission?
    ResourceActionsConfig.action(resource, action)
  end
  
  def resource_config
    return nil unless valid_permission?
    ResourceActionsConfig.resource(resource)
  end
  
  def display_name
    return permission_key unless valid_permission?
    ResourceActionsConfig.permission_display_name(permission_key)
  end
  
  def valid_permission?
    ResourceActionsConfig.valid_permission?(permission_key)
  end
  
  private
  
  def permission_key_must_be_valid
    return if permission_key.blank?
    
    unless ResourceActionsConfig.valid_permission?(permission_key)
      errors.add(:permission_key, "is not a valid permission key. Must be in format 'resource.action'")
    end
  end
end