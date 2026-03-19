# == Schema Information
#
# Table name: account_custom_role_resource_scopes
#
#  id              :uuid             not null, primary key
#  custom_role_id  :uuid             not null
#  account_id      :uuid             not null
#  resource_type   :string(100)      not null
#  resource_id     :uuid             not null
#  actions         :jsonb            not null, default([])
#  created_by_id   :uuid
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#

class AccountCustomRoleResourceScope < ApplicationRecord
  # ============================================================
  # ASSOCIATIONS
  # ============================================================
  belongs_to :account_custom_role,
             foreign_key: :account_custom_role_id
  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true

  # ============================================================
  # VALIDATIONS
  # ============================================================
  validates :account_custom_role_id, presence: true
  validates :account_id, presence: true
  validates :resource_type, presence: true, length: { maximum: 100 }
  validates :resource_id, presence: true
  validates :actions, presence: true
  validate :actions_must_be_array
  validate :actions_must_be_valid
  validate :account_must_match_custom_role

  # ============================================================
  # SCOPES
  # ============================================================
  scope :for_role, ->(role) { where(account_custom_role_id: role.id) }
  scope :for_account, ->(account) { where(account_id: account.id) }
  scope :for_resource_type, ->(type) { where(resource_type: type.to_s) }
  scope :for_resource, ->(type, id) { where(resource_type: type.to_s, resource_id: id) }
  scope :with_action, ->(action) { where("actions @> ?", [action].to_json) }
  scope :ordered, -> { order(:resource_type, :created_at) }

  # ============================================================
  # CONSTANTS
  # ============================================================
  VALID_ACTIONS = %w[read create update delete execute manage].freeze
  ALL_ACTIONS_WILDCARD = '*'

  # ============================================================
  # INSTANCE METHODS
  # ============================================================

  # Verifica se uma ação está permitida
  def allows_action?(action)
    return true if allows_all?
    actions.include?(action.to_s)
  end

  # Verifica se permite todas as ações
  def allows_all?
    actions.include?(ALL_ACTIONS_WILDCARD)
  end

  # Adiciona uma ação
  def add_action(action)
    return true if allows_action?(action)

    new_actions = actions + [action.to_s]
    update(actions: new_actions.uniq)
  end

  # Remove uma ação
  def remove_action(action)
    return false unless allows_action?(action)

    new_actions = actions - [action.to_s]
    update(actions: new_actions)
  end

  # Permite todas as ações
  def allow_all!
    update(actions: [ALL_ACTIONS_WILDCARD])
  end

  # Remove permissão de todas as ações (volta para apenas as especificadas)
  def restrict_to_actions(action_list)
    action_list = Array(action_list).map(&:to_s)
    update(actions: action_list)
  end

  # ============================================================
  # CLASS METHODS
  # ============================================================

  # Criar múltiplos scopes em bulk
  def self.bulk_create_for_role(account_custom_role, scopes_data)
    return 0 if scopes_data.blank?

    created_count = 0
    Array(scopes_data).each do |scope_data|
      begin
        create!(
          account_custom_role: account_custom_role,
          account_id: account_custom_role.account_id,
          resource_type: scope_data[:resource_type],
          resource_id: scope_data[:resource_id],
          actions: Array(scope_data[:actions]),
          created_by_id: scope_data[:created_by_id]
        )
        created_count += 1
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.warn "Failed to create resource scope: #{e.message}"
        next
      end
    end

    created_count
  end

  # Listar scopes agrupados por tipo de recurso
  def self.scopes_by_resource_type_for_role(account_custom_role)
    for_role(account_custom_role)
      .group_by(&:resource_type)
      .transform_values do |scopes|
        scopes.map do |scope|
          {
            resource_id: scope.resource_id,
            actions: scope.actions,
            allows_all: scope.allows_all?
          }
        end
      end
  end

  # Verificar se role pode acessar recurso específico
  def self.can_access?(account_custom_role, resource_type, resource_id, action)
    scope = for_resource(resource_type, resource_id)
            .where(account_custom_role: account_custom_role)
            .first

    return false unless scope
    scope.allows_action?(action)
  end

  # Listar IDs de recursos acessíveis de um tipo para uma role
  def self.accessible_resource_ids(account_custom_role, resource_type, action = 'read')
    for_resource_type(resource_type)
      .where(account_custom_role: account_custom_role)
      .select { |scope| scope.allows_action?(action) }
      .pluck(:resource_id)
  end

  # ============================================================
  # SERIALIZATION
  # ============================================================

  def as_json(options = {})
    super(options.merge(
      methods: [:allows_all],
      include: {
        created_by: { only: [:id, :name, :email] }
      }
    ))
  end

  private

  # ============================================================
  # VALIDATIONS
  # ============================================================

  def actions_must_be_array
    unless actions.is_a?(Array)
      errors.add(:actions, 'must be an array')
    end
  end

  def actions_must_be_valid
    return if actions.blank?
    return if !actions.is_a?(Array)

    # Se tem wildcard, permite
    return if actions.include?(ALL_ACTIONS_WILDCARD)

    # Validar que todas as ações são válidas
    invalid_actions = actions - VALID_ACTIONS
    if invalid_actions.any?
      errors.add(:actions, "contains invalid actions: #{invalid_actions.join(', ')}")
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
