module RoleHelper
  def load_roles
    @roles = Role.includes(:role_permissions_actions, :users)
  end

  def role_serializer(role)
    # Obter todas as permissões por recurso usando a nova estrutura
    permissions_by_resource = role.permissions_by_resource
    
    # Contar o número total de ações permitidas
    total_actions = permissions_by_resource.values.sum(&:size)
    
    {
      id: role.id,
      key: role.key,
      name: role.name,
      description: role.description,
      system: role.system,
      type: role.type,
      permissions_by_resource: permissions_by_resource,
      permissions_count: total_actions,
      users_count: role.users.count,
      created_at: role.created_at,
      updated_at: role.updated_at
    }
  end
end
