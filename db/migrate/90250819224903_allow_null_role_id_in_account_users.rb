class AllowNullRoleIdInAccountUsers < ActiveRecord::Migration[7.1]
  def change
    # Allow NULL for role_id since users can have either:
    # - role_id (system role) OR
    # - account_custom_role_id (custom role)
    # The check constraint 'check_not_both_roles' ensures they don't have both
    change_column_null :account_users, :role_id, true
  end
end
