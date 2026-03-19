# == Schema Information
#
# Table name: roles
#
#  id           :uuid             not null, primary key
#  key          :string           not null
#  name         :string           not null
#  description  :text
#  system       :boolean          default(FALSE), not null
#  type         :string           default("user"), not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#

class Role < ApplicationRecord
  # Desabilitar Single Table Inheritance para usar a coluna 'type' para nossos próprios propósitos
  self.inheritance_column = :_type_disabled
  
  has_many :role_permissions_actions, dependent: :destroy
  has_many :user_roles, dependent: :destroy
  has_many :users, through: :user_roles

  validates :key, presence: true, uniqueness: true
  validates :name, presence: true, uniqueness: { scope: :type }
  validates :type, presence: true, inclusion: { in: %w[user account] }

  scope :system_roles, -> { where(system: true) }
  scope :non_system_roles, -> { where(system: false) }
  scope :user_type, -> { where(type: 'user') }
  scope :account_type, -> { where(type: 'account') }
  
  # Proteção para roles do sistema
  before_destroy :prevent_system_role_deletion
  before_update :prevent_system_role_key_modification

  # Verifica se é uma role do tipo usuário
  def user_type?
    type == 'user'
  end

  # Verifica se é uma role do tipo conta
  def account_type?
    type == 'account'
  end

  # Verifica se é uma role do sistema
  def system_role?
    system
  end

  # Verifica se é uma role personalizada
  def custom_role?
    !system
  end

  # Verifica se a role pode ser excluída
  def can_be_deleted?
    # Não pode excluir se é role do sistema ou tem usuários associados
    !system && user_roles.count == 0
  end
  
  private
  
  def prevent_system_role_deletion
    throw :abort if system?
  end
  
  def prevent_system_role_key_modification
    if system? && saved_change_to_attribute?(:key)
      errors.add(:key, "cannot be modified for system roles")
      throw :abort
    end
  end

  public

  # Método para criar as roles padrão do sistema
  def self.seed_default_roles!
    # Verificar se já existe o arquivo de seeds para o RBAC
    if File.exist?(Rails.root.join('db', 'seeds', 'rbac.rb'))
      # Carregar o seed de RBAC
      Rails.logger.info "⚙️ Carregando seed de RBAC..."
      load Rails.root.join('db', 'seeds', 'rbac.rb')
    else
      Rails.logger.warn "⚠️ Arquivo de seed RBAC não encontrado."
    end
    
    Rails.logger.info "✅ Seed de roles concluído!"
  end

  # Métodos adaptados para o novo sistema RBAC
  # Adiciona uma permissão à role
  # @param permission_key [String] Chave da permissão no formato 'recurso.ação'
  def add_permission(permission_key)
    return false unless permission_key.present?
    return false unless ResourceActionsConfig.valid_permission?(permission_key)

    # Criar a associação direta se não existir
    role_permissions_actions.find_or_create_by!(permission_key: permission_key)
    true
  end

  # Remove uma permissão da role
  # @param permission_key [String] Chave da permissão no formato 'recurso.ação'
  def remove_permission(permission_key)
    return false unless permission_key.present?

    # Buscar e remover a associação direta
    role_permission_action = role_permissions_actions.find_by(permission_key: permission_key)
    return false unless role_permission_action
    
    role_permission_action.destroy
    true
  end

  # Verifica se a role tem uma determinada permissão
  # @param permission_key [String] Chave da permissão no formato 'recurso.ação'
  # @return [Boolean] true se tem a permissão, false caso contrário
  def has_permission?(permission_key)
    return false unless permission_key.present?
    
    # Verificar se a permissão está diretamente associada
    role_permissions_actions.exists?(permission_key: permission_key)
  end

  # Lista todas as permissões da role no formato 'recurso.ação'
  # @return [Array<String>] Lista de permissões
  def permission_keys
    role_permissions_actions.pluck(:permission_key)
  end

  # Get permissions organized by resource
  def permissions_by_resource
    permissions = role_permissions_actions.pluck(:permission_key)
    
    permissions.group_by { |permission| permission.split('.').first }
              .transform_values { |perms| perms.map { |perm| perm.split('.').last } }
  end

  private
  
  def prevent_system_role_deletion
    throw :abort if system?
  end
  
  def prevent_system_role_key_modification
    if system? && saved_change_to_attribute?(:key)
      errors.add(:key, "cannot be modified for system roles")
      throw :abort
    end
  end
end