# frozen_string_literal: true

class UserPermissionService
  attr_reader :user

  def initialize(user)
    @user = user
  end

  # Verifica se o usuário tem permissão para realizar uma ação específica em um recurso
  def can?(resource, action)
    # Criar a chave de permissão no formato "resource.action"
    permission_key = "#{resource}.#{action}"

    # Verificar se o usuário tem essa permissão através de suas roles
    user_roles.joins(role: :role_permissions_actions).where(
      role_permissions_actions: { permission_key: permission_key }
    ).exists?
  end

  # Verifica se o usuário tem pelo menos uma das permissões especificadas
  def can_any?(permissions)
    permissions.any? do |permission|
      resource, action = permission.split('.')
      can?(resource, action)
    end
  end

  # Verifica se o usuário tem todas as permissões especificadas
  def can_all?(permissions)
    permissions.all? do |permission|
      resource, action = permission.split('.')
      can?(resource, action)
    end
  end

  # Retorna todas as permissões do usuário
  def all_permissions(user_id = nil)
    return [] unless user

    # Construir query base
    query = user_roles.joins(role: :role_permissions_actions)

    # Filtrar por conta se especificada
    query = query.where(user_id: user_id) if user_id.present?

    # Obter todas as permission_keys
    query.pluck('role_permissions_actions.permission_key').uniq
  end
  
  # Alias para compatibilidade
  def permissions
    all_permissions
  end

  # Retorna as permissões agrupadas por recurso
  def permissions_by_resource(user_id = nil)
    permissions = if user_id
      user_roles.joins(role: :role_permissions_actions)
               .where(user_id: user_id)
               .pluck('role_permissions_actions.permission_key')
               .uniq
    else
      all_permissions
    end
    
    permissions.group_by { |permission| permission.split('.').first }
               .transform_values { |perms| perms.map { |perm| perm.split('.').last } }
  end

  # Verifica se o usuário tem uma role específica
  # @param role_key [String] Chave da role (ex: 'account_owner')
  # @param user_id [String, UUID] ID opcional de usuário para verificar role específica do usuário
  def has_role?(role_key, user_id = nil)
    return false unless user

    if user_id
      # Verificar role específica para um usuário
      user.user_roles.joins(:role).where(
        user: user_id,
        roles: { key: role_key }
      ).exists?
    else
      # Verificar role global (para qualquer usuário)
      user.user_roles.joins(:role).where(
        roles: { key: role_key }
      ).exists?
    end
  end

  private

  def user_roles
    @user_roles ||= user.user_roles
  end
end
