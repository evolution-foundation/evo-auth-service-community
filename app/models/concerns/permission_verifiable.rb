# frozen_string_literal: true

module PermissionVerifiable
  extend ActiveSupport::Concern

  # Verifica se o usuário tem permissão para realizar uma ação específica
  # @param permission_key [String] A chave da permissão no formato "resource.action" (ex: 'users.read', 'accounts.create')
  # @return [Boolean] true se o usuário tem permissão, false caso contrário
  def has_permission?(permission_key)
    # Construir query base
    query = user_roles.joins(role: :role_permissions_actions)
                     .where(role_permissions_actions: { permission_key: permission_key })

    # Verificar se existe pelo menos uma role com a permissão
    query.exists?
  end

  # Método para validação de permissão - usado pelos endpoints
  # @param permission_key [String] A chave da permissão no formato "resource.action"
  # @return [Boolean] true se o usuário tem permissão, false caso contrário
  def check_permission(permission_key)
    has_permission?(permission_key)
  end

  # Lista todas as permissões do usuário no formato "resource.action"
  # @return [Array<String>] Lista de chaves de permissão
  def all_permissions
    user_roles.joins(role: :role_permissions_actions)
              .pluck('role_permissions_actions.permission_key').uniq.sort
  end

  # Lista permissões agrupadas por recurso
  # @return [Hash] Hash com recursos e suas ações permitidas
  def permissions_by_resource
    permissions_by_resource = {}

    all_permissions.each do |permission_key|
      resource, action = permission_key.split('.', 2)
      next unless resource && action
      
      permissions_by_resource[resource] ||= {}
      permissions_by_resource[resource][action] = true
    end
    
    permissions_by_resource
  end

  alias_method :all_permissions_by_resource, :permissions_by_resource
end
