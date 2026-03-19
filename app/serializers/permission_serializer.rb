# frozen_string_literal: true

module PermissionSerializer
  extend self

  def full(permission)
    return nil unless permission

    {
      id: permission.id,
      role_id: permission.role_id,
      resource: permission.resource,
      actions: permission.actions,
      created_at: permission.created_at,
      updated_at: permission.updated_at
    }
  end
end
