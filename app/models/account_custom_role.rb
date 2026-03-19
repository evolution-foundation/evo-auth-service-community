# == Schema Information
#
# Table name: account_custom_roles
#
#  id             :uuid             not null, primary key
#  account_id     :uuid             not null
#  key            :string(100)      not null
#  name           :string(255)      not null
#  description    :text
#  is_active      :boolean          default(TRUE), not null
#  created_by_id  :uuid
#  updated_by_id  :uuid
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#

class AccountCustomRole < ApplicationRecord
  # ============================================================
  # ASSOCIATIONS
  # ============================================================
  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :updated_by, class_name: 'User', optional: true

  has_many :account_custom_role_permissions,
           foreign_key: :account_custom_role_id,
           dependent: :destroy
  has_many :account_custom_role_resource_scopes,
           foreign_key: :account_custom_role_id,
           dependent: :destroy
  has_many :account_users,
           foreign_key: :account_custom_role_id,
           dependent: :nullify

  # ============================================================
  # VALIDATIONS
  # ============================================================
  validates :account_id, presence: true
  validates :key, presence: true,
            length: { maximum: 100 },
            uniqueness: { scope: :account_id, case_sensitive: false },
            format: { with: /\A[a-z0-9_]+\z/, message: 'only allows lowercase letters, numbers and underscores' }
  validates :name, presence: true,
            length: { maximum: 255 },
            uniqueness: { scope: :account_id }

  # ============================================================
  # SCOPES
  # ============================================================
  scope :active, -> { where(is_active: true) }
  scope :inactive, -> { where(is_active: false) }
  scope :for_account, ->(account) { where(account_id: account.id) }
  scope :ordered, -> { order(:name) }

  # ============================================================
  # CALLBACKS
  # ============================================================
  before_validation :normalize_key

  # ============================================================
  # RESOURCE-LEVEL PERMISSIONS
  # ============================================================

  # Adicionar permissão resource-level
  def add_permission(permission_key)
    return false unless ResourceActionsConfig.valid_permission?(permission_key)

    account_custom_role_permissions.find_or_create_by!(
      account_id: account_id,
      permission_key: permission_key
    )
    true
  rescue ActiveRecord::RecordInvalid
    false
  end

  # Adicionar múltiplas permissões
  def add_permissions(permission_keys)
    permission_keys = Array(permission_keys)
    valid_keys = permission_keys.select { |key| ResourceActionsConfig.valid_permission?(key) }

    valid_keys.each do |permission_key|
      add_permission(permission_key)
    end

    valid_keys.size
  end

  # Remover permissão
  def remove_permission(permission_key)
    account_custom_role_permissions
      .where(permission_key: permission_key)
      .destroy_all
      .size
  end

  # Atualizar permissões (substituir todas)
  def update_permissions(permission_keys)
    permission_keys = Array(permission_keys)
    valid_keys = permission_keys.select { |key| ResourceActionsConfig.valid_permission?(key) }

    transaction do
      # Remover todas permissões existentes
      account_custom_role_permissions.destroy_all

      # Adicionar novas permissões
      valid_keys.each do |permission_key|
        account_custom_role_permissions.create!(
          account_id: account_id,
          permission_key: permission_key
        )
      end
    end

    valid_keys.size
  end

  # Verificar se tem permissão
  def has_permission?(permission_key)
    account_custom_role_permissions.exists?(permission_key: permission_key)
  end

  # Listar todas permissões
  def permission_keys
    account_custom_role_permissions.pluck(:permission_key).sort
  end

  # Permissões agrupadas por recurso
  def permissions_by_resource
    permissions = permission_keys

    permissions.group_by { |key| key.split('.').first }
               .transform_values { |perms| perms.map { |p| p.split('.').last } }
  end

  # ============================================================
  # INSTANCE-LEVEL PERMISSIONS (RESOURCE SCOPES)
  # ============================================================

  # Adicionar scope de recurso específico
  def add_resource_scope(resource_type, resource_id, actions = ['read'])
    actions = Array(actions)

    account_custom_role_resource_scopes.create!(
      account_id: account_id,
      resource_type: resource_type.to_s,
      resource_id: resource_id,
      actions: actions
    )
  end

  # Atualizar scope de recurso
  def update_resource_scope(resource_type, resource_id, actions)
    scope = account_custom_role_resource_scopes.find_by(
      resource_type: resource_type.to_s,
      resource_id: resource_id
    )

    return false unless scope

    scope.update(actions: Array(actions))
  end

  # Remover scope de recurso
  def remove_resource_scope(resource_type, resource_id)
    account_custom_role_resource_scopes
      .where(resource_type: resource_type.to_s, resource_id: resource_id)
      .destroy_all
      .size
  end

  # Verificar se pode acessar recurso específico
  def can_access_resource?(resource_type, resource_id, action)
    scope = account_custom_role_resource_scopes.find_by(
      resource_type: resource_type.to_s,
      resource_id: resource_id
    )

    return false unless scope
    scope.allows_action?(action)
  end

  # Listar recursos acessíveis de um tipo
  def accessible_resource_ids(resource_type, action = 'read')
    account_custom_role_resource_scopes
      .where(resource_type: resource_type.to_s)
      .select { |scope| scope.allows_action?(action) }
      .pluck(:resource_id)
  end

  # Listar todos os scopes
  def resource_scopes
    account_custom_role_resource_scopes
      .select(:resource_type, :resource_id, :actions)
      .group_by(&:resource_type)
      .transform_values do |scopes|
        scopes.map do |scope|
          {
            resource_id: scope.resource_id,
            actions: scope.actions
          }
        end
      end
  end

  # ============================================================
  # STATUS METHODS
  # ============================================================

  def activate!
    update!(is_active: true)
  end

  def deactivate!
    update!(is_active: false)
  end

  def toggle_active!
    update!(is_active: !is_active)
  end

  # ============================================================
  # INFO METHODS
  # ============================================================

  def users_count
    account_users.count
  end

  def permissions_count
    account_custom_role_permissions.count
  end

  def resource_scopes_count
    account_custom_role_resource_scopes.count
  end

  # Serialização para API
  def as_json(options = {})
    super(options.merge(
      methods: [:users_count, :permissions_count, :resource_scopes_count],
      include: {
        created_by: { only: [:id, :name, :email] },
        updated_by: { only: [:id, :name, :email] }
      }
    ))
  end

  private

  def normalize_key
    # Generate key from name if key is blank
    if key.blank? && name.present?
      self.key = name.to_s.downcase.strip
                     .gsub(/[^a-z0-9\s_]/, '') # Remove caracteres especiais
                     .gsub(/\s+/, '_')          # Substitui espaços por underscores
                     .gsub(/_+/, '_')           # Remove underscores duplicados
                     .gsub(/^_|_$/, '')         # Remove underscores no início/fim
    elsif key.present?
      self.key = key.to_s.downcase.strip
    end
  end
end
