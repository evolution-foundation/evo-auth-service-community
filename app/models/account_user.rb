# == Schema Information
#
# Table name: account_users
#
#  id             :uuid             not null, primary key
#  active_at      :datetime
#  auto_offline   :boolean          default(TRUE), not null
#  availability   :integer          default("online"), not null
#  role_id        :uuid
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :uuid
#  inviter_id     :uuid
#  user_id        :uuid
#

class AccountUser < ApplicationRecord
  include AvailabilityStatusable

  belongs_to :account
  belongs_to :user
  belongs_to :inviter, class_name: 'User', optional: true
  belongs_to :role, optional: true  # System role
  belongs_to :account_custom_role,  # Custom role (NOVO)
             foreign_key: :account_custom_role_id,
             optional: true

  enum availability: { online: 0, offline: 1, busy: 2 }

  accepts_nested_attributes_for :account

  validates :user_id, uniqueness: { scope: :account_id }
  validate :must_have_one_role

  # ============================================================
  # ROLE TYPE DETECTION
  # ============================================================

  # Qual tipo de role está usando?
  def role_type
    return :system if role_id.present?
    return :custom if account_custom_role_id.present?
    nil
  end

  def has_system_role?
    role_type == :system
  end

  def has_custom_role?
    role_type == :custom
  end

  # Retorna a role ativa (system ou custom)
  def active_role
    return role if has_system_role?
    return account_custom_role if has_custom_role?
    nil
  end

  def role_data
    return nil unless active_role

    {
      id: active_role.id,
      key: active_role.key,
      name: active_role.name,
      type: role_type
    }
  end

  # ============================================================
  # RESOURCE-LEVEL PERMISSIONS
  # ============================================================

  # Permissões básicas sempre liberadas para qualquer usuário autenticado
  BASIC_READ_PERMISSIONS = [
    'accounts.read',      # Informações da própria conta
    'labels.read',        # Labels/tags são recursos básicos
    'dashboard.read',     # Dashboard básico
    'inboxes.read',       # Lista de inboxes (necessário para filtros)
    'teams.read',         # Lista de times (necessário para filtros)
    'users.read'          # Lista de usuários (necessário para assignee, filtros, etc)
  ].freeze

  # RBAC methods - use own for permissions
  def permissions
    return BASIC_READ_PERMISSIONS.dup unless persisted?

    role_permissions = case role_type
    when :system
      # System role: usar role_permissions_actions
      RolePermissionsAction.where(role_id: role_id)
                          .pluck(:permission_key)
    when :custom
      # Custom role: usar account_custom_role_permissions
      AccountCustomRolePermission.where(account_custom_role_id: account_custom_role_id)
                                 .pluck(:permission_key)
    else
      []
    end

    # Merge basic permissions with role-specific permissions
    (BASIC_READ_PERMISSIONS + role_permissions).uniq.sort
  end

  def has_permission?(permission_key)
    return false unless permission_key.present?

    # Always allow basic read permissions for authenticated users
    return true if BASIC_READ_PERMISSIONS.include?(permission_key)

    case role_type
    when :system
      RolePermissionsAction.exists?(role_id: role_id, permission_key: permission_key)
    when :custom
      AccountCustomRolePermission.exists?(
        account_custom_role_id: account_custom_role_id,
        permission_key: permission_key
      )
    else
      false
    end
  end

  # ============================================================
  # INSTANCE-LEVEL PERMISSIONS (NOVO)
  # ============================================================

  # Verifica se pode acessar recurso específico
  def can_access_resource?(resource_type, resource_id, action)
    # 1. Primeiro verificar permissão resource-level
    resource_key = resource_type.to_s.tableize # Pipeline -> pipelines
    return false unless has_permission?("#{resource_key}.#{action}")

    # 2. Se tem custom role, verificar scopes
    if has_custom_role?
      scopes = AccountCustomRoleResourceScope.for_resource(resource_type, resource_id)
                                             .where(account_custom_role_id: account_custom_role_id)

      # Se não há scope específico, permite (resource-level já aprovou)
      return true if scopes.empty?

      # Se há scope, verificar se permite a ação
      scopes.any? { |scope| scope.allows_action?(action) }
    else
      # System role: não tem instance-level, apenas resource-level
      true
    end
  end

  # Listar recursos acessíveis de um tipo
  def accessible_resource_ids(resource_type, action = 'read')
    # Verificar permissão resource-level
    resource_key = resource_type.to_s.tableize
    return [] unless has_permission?("#{resource_key}.#{action}")

    # System role: retorna :all (não tem instance-level)
    return :all if has_system_role?

    # Custom role: buscar scopes
    scopes = AccountCustomRoleResourceScope
               .for_role(account_custom_role)
               .for_resource_type(resource_type)

    # Se não há scopes, permite todos
    return :all if scopes.empty?

    # Filtrar por ação
    scopes.select { |s| s.allows_action?(action) }
          .pluck(:resource_id)
  end

  # RBAC permission checking methods
  def administrator?
    has_any_role?(['account_owner'])
  end

  def agent?
    has_role?('agent') && !administrator?
  end

  def account_owner?
    has_role?('account_owner')
  end

  # Role checking methods
  def has_role?(role_key)
    return false unless persisted?

    if has_system_role?
      # Check role directly using own role_id
      Role.exists?(id: role_id, key: role_key)
    elsif has_custom_role?
      # Check custom role key
      AccountCustomRole.exists?(id: account_custom_role_id, key: role_key)
    else
      false
    end
  end

  def has_any_role?(role_keys)
    return false unless persisted?
    return false if role_keys.blank?

    if has_system_role?
      # Check if any of the role keys match our role_id
      Role.exists?(id: role_id, key: role_keys)
    elsif has_custom_role?
      # Check if any of the role keys match our account_custom_role_id
      AccountCustomRole.exists?(id: account_custom_role_id, key: role_keys)
    else
      false
    end
  end

  # Permission checking methods  
  def can_manage_users?
    has_permission?('users.manage') || has_permission?('users.create')
  end

  def can_manage_roles?
    has_permission?('roles.manage') || has_permission?('roles.create')
  end

  def can_manage_oauth?
    has_permission?('oauth.manage') || administrator?
  end

  def can_manage_features?
    has_permission?('features.manage') || account_owner?
  end

  def can_manage_account?
    has_permission?('accounts.manage') || account_owner?
  end

  def push_event_data
    {
      id: id,
      availability: availability,
      role: role_data,
      user_id: user_id
    }
  end

  # Create user role in account - must be called explicitly
  def self.create_with_role!(user:, account:, role_key:, inviter: nil)
    role = Role.find_by!(key: role_key)

    transaction do
      account_user = create!(
        user: user,
        account: account,
        role_id: role.id,
        inviter: inviter
      )

      # Remove any existing account roles before assigning the new one
      # This ensures we don't have multiple account roles for the same user
      existing_account_roles = user.user_roles.joins(:role).where(roles: { system: false })
      existing_account_roles.destroy_all if existing_account_roles.exists?

      # Only create UserRole if it doesn't exist yet
      UserRole.find_or_create_by!(
        user: user,
        role: role
      ) do |user_role|
        user_role.granted_by = inviter
        user_role.granted_at = Time.current
      end

      account_user
    end
  end

  # Create user with custom role in account
  def self.create_with_custom_role!(user:, account:, account_custom_role:, inviter: nil)
    transaction do
      create!(
        user: user,
        account: account,
        account_custom_role_id: account_custom_role.id,
        inviter: inviter
      )
    end
  end

  private

  # Validação: deve ter uma role (system OU custom), mas não ambas
  def must_have_one_role
    # Se ambos estão presentes, o check constraint do banco vai pegar
    # Aqui só validamos se pelo menos um está presente
    if role_id.blank? && account_custom_role_id.blank?
      errors.add(:base, 'must have either a system role or custom role')
    end
  end
end
