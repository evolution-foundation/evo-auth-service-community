# == Schema Information
#
# Table name: account_custom_role_permissions
#
#  id              :uuid             not null, primary key
#  custom_role_id  :uuid             not null
#  account_id      :uuid             not null
#  permission_key  :string(100)      not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#

class AccountCustomRolePermission < ApplicationRecord
  # ============================================================
  # ASSOCIATIONS
  # ============================================================
  belongs_to :account_custom_role,
             foreign_key: :account_custom_role_id
  belongs_to :account

  # ============================================================
  # VALIDATIONS
  # ============================================================
  validates :account_custom_role_id, presence: true
  validates :account_id, presence: true
  validates :permission_key, presence: true,
            length: { maximum: 100 },
            uniqueness: { scope: :account_custom_role_id }
  validate :permission_key_must_be_valid
  validate :account_must_match_custom_role

  # ============================================================
  # SCOPES
  # ============================================================
  scope :for_role, ->(role) { where(account_custom_role_id: role.id) }
  scope :for_account, ->(account) { where(account_id: account.id) }
  scope :for_resource, ->(resource) { where("permission_key LIKE ?", "#{resource}.%") }
  scope :for_action, ->(action) { where("permission_key LIKE ?", "%.#{action}") }
  scope :ordered, -> { order(:permission_key) }

  # ============================================================
  # INSTANCE METHODS
  # ============================================================

  # Retorna o recurso da permissão (ex: 'contacts' para 'contacts.read')
  def resource
    permission_key.split('.').first if permission_key.present?
  end

  # Retorna a ação da permissão (ex: 'read' para 'contacts.read')
  def action
    permission_key.split('.').last if permission_key.present?
  end

  # Retorna o nome de exibição da permissão
  def display_name
    return permission_key unless valid_permission?
    ResourceActionsConfig.permission_display_name(permission_key)
  end

  # Retorna a configuração da ação
  def action_config
    return nil unless valid_permission?
    ResourceActionsConfig.action(resource, action)
  end

  # Retorna a configuração do recurso
  def resource_config
    return nil unless valid_permission?
    ResourceActionsConfig.resource(resource)
  end

  # Verifica se a permissão é válida
  def valid_permission?
    ResourceActionsConfig.valid_permission?(permission_key)
  end

  # ============================================================
  # CLASS METHODS
  # ============================================================

  # Criar múltiplas permissões em bulk
  def self.bulk_create_for_role(account_custom_role, permission_keys)
    return 0 if permission_keys.blank?

    permission_keys = Array(permission_keys)
    valid_keys = permission_keys.select { |key| ResourceActionsConfig.valid_permission?(key) }

    created_count = 0
    valid_keys.each do |permission_key|
      begin
        create!(
          account_custom_role: account_custom_role,
          account_id: account_custom_role.account_id,
          permission_key: permission_key
        )
        created_count += 1
      rescue ActiveRecord::RecordInvalid
        # Ignora se já existe
        next
      end
    end

    created_count
  end

  # Substituir todas as permissões de uma role
  def self.replace_for_role(account_custom_role, permission_keys)
    transaction do
      where(account_custom_role: account_custom_role).destroy_all
      bulk_create_for_role(account_custom_role, permission_keys)
    end
  end

  # Listar permissões de uma role
  def self.permissions_for_role(account_custom_role)
    where(account_custom_role: account_custom_role).pluck(:permission_key).uniq
  end

  # Listar permissões agrupadas por recurso
  def self.permissions_by_resource_for_role(account_custom_role)
    permissions = permissions_for_role(account_custom_role)

    permissions.group_by { |key| key.split('.').first }
               .transform_values { |perms| perms.map { |p| p.split('.').last } }
  end

  # ============================================================
  # SERIALIZATION
  # ============================================================

  def as_json(options = {})
    super(options.merge(
      methods: [:resource, :action, :display_name]
    ))
  end

  private

  # ============================================================
  # VALIDATIONS
  # ============================================================

  def permission_key_must_be_valid
    return if permission_key.blank?

    unless ResourceActionsConfig.valid_permission?(permission_key)
      errors.add(:permission_key, 'is not a valid permission')
    end
  end

  def account_must_match_custom_role
    return if account_id.blank? || account_custom_role_id.blank?
    return if account_custom_role.nil?

    if account_id != account_custom_role.account_id
      errors.add(:account_id, 'must match custom role account')
    end
  end
end
