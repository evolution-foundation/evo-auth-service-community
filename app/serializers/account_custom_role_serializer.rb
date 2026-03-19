# frozen_string_literal: true

module AccountCustomRoleSerializer
  extend self

  def full(custom_role)
    return nil unless custom_role

    {
      id: custom_role.id,
      account_id: custom_role.account_id,
      name: custom_role.name,
      description: custom_role.description,
      permissions: custom_role.account_custom_role_permissions.map do |perm|
        {
          id: perm.id,
          resource: perm.resource,
          action: perm.action,
          permission_key: perm.permission_key
        }
      end,
      resource_scopes: custom_role.account_custom_role_resource_scopes.map do |scope|
        {
          id: scope.id,
          resource_type: scope.resource_type,
          resource_id: scope.resource_id
        }
      end,
      created_at: custom_role.created_at,
      updated_at: custom_role.updated_at
    }
  end

  def basic(custom_role)
    return nil unless custom_role

    {
      id: custom_role.id,
      name: custom_role.name,
      description: custom_role.description
    }
  end
end
