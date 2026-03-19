# == Schema Information
#
# Table name: user_roles
#
#  id          :bigint           not null, primary key
#  user_id     :bigint           not null
#  role_id     :bigint           not null
#  granted_by_id :bigint
#  granted_at  :datetime         default(CURRENT_TIMESTAMP)
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#

class UserRole < ApplicationRecord
  belongs_to :user
  belongs_to :role
  belongs_to :granted_by, class_name: 'User', optional: true

  validates :user_id, uniqueness: { scope: :role_id }

  scope :for_user, ->(user) { where(user: user) }
  scope :for_role, ->(role) { where(role: role) }
  scope :system_roles, -> { joins(:role).where(roles: { system: true }) }
  scope :account_roles, -> { joins(:role).where(roles: { system: false }) }

  before_validation :set_granted_at, on: :create

  def self.assign_role_to_user(user, role, granted_by = nil)
    find_or_create_by(
      user_id: user.id,
      role_id: role.id
    ) do |user_role|
      user_role.granted_by = granted_by
      user_role.granted_at = Time.current
    end
  end

  def self.remove_role_from_user(user, role)
    where(user: user, role: role).destroy_all
  end

  def self.user_has_role?(user, role_key)
    joins(:role)
      .where(user: user)
      .where(roles: { key: role_key })
      .exists?
  end

  def self.user_permissions(user, account = nil)
    joins(role: :role_permissions_actions)
      .where(user: user)
      .pluck('role_permissions_actions.permission_key')
      .uniq
  end

  def role_name
    role.name
  end

  def role_display_name
    role.display_name
  end

  def system_role?
    role.system_role?
  end

  def account_role?
    !role.system_role?
  end

  private

  def set_granted_at
    self.granted_at ||= Time.current
  end
end