# frozen_string_literal: true

module RoleSerializer
  extend self

  def full(role)
    return nil unless role

    {
      id: role.id,
      key: role.key,
      name: role.name,
      description: role.description,
      system: role.system,
      permissions: role.permissions_by_resource,
      created_at: role.created_at,
      updated_at: role.updated_at
    }
  end

  def basic(role)
    return nil unless role

    {
      id: role.id,
      key: role.key,
      name: role.name,
      description: role.description,
      system: role.system
    }
  end
end
