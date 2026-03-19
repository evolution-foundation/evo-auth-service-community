# == Schema Information
#
# Table name: accounts
#
#  id                    :uuid             not null, primary key
#  auto_resolve_duration :integer
#  custom_attributes     :jsonb
#  domain                :string(100)
#  feature_flags         :bigint           default(0), not null
#  internal_attributes   :jsonb            not null
#  locale                :integer          default("en")
#  name                  :string           not null
#  settings              :jsonb
#  status                :integer          default("active")
#  support_email         :string(100)
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#

class Account < ApplicationRecord
  alias_attribute :total_conversations, "total_conversations"
  alias_attribute :total_inboxes, "total_inboxes"

  # used for single column multi flags
  include FlagShihTzu
  include AccessTokenable

  SETTINGS_PARAMS_SCHEMA = {
    'type': "object",
    'properties':
      {
        'auto_resolve_after': { 'type': %w[integer null], 'minimum': 10, 'maximum': 1_439_856 },
        'auto_resolve_message': { 'type': %w[string null] },
        'auto_resolve_ignore_waiting': { 'type': %w[boolean null] },
        'audio_transcriptions': { 'type': %w[boolean null] },
        'auto_resolve_label': { 'type': %w[string null] }
      },
    'required': [],
    'additionalProperties': true
  }.to_json.freeze

  DEFAULT_QUERY_SETTING = {
    flag_query_mode: :bit_operator,
    check_for_column: false
  }.freeze

  validates :domain, length: { maximum: 100 }
  validates :name, presence: true

  store_accessor :settings, :auto_resolve_after, :auto_resolve_message, :auto_resolve_ignore_waiting
  store_accessor :settings, :audio_transcriptions, :auto_resolve_label

  # Enums
  enum status: { active: 0, suspended: 1 }
  enum locale: { en: 0, pt: 1, 'pt-BR': 2, es: 3, fr: 4, de: 5 }

  # Associations
  has_many :account_users, dependent: :destroy_async
  has_many :users, through: :account_users
  has_many :oauth_applications, dependent: :destroy
  # user_roles não tem account_id diretamente - relação é indireta através de users
  # Não deve ser deletado quando account é deletado, pois users podem ter outras contas
  has_many :account_custom_roles, dependent: :destroy

  # Callbacks
  after_create_commit :notify_creation

  def agents
    users.joins(account_users: :role).where(roles: { key: "agent" })
  end

  def administrators
    users.joins(account_users: :role).where(roles: { key: "account_owner" })
  end

  def webhook_data
    {
      id: id,
      name: name,
      status: status,
      locale: locale,
      created_at: created_at,
      updated_at: updated_at
    }
  end

  # Plans/features removed in community edition — stub methods return safe defaults
  def active_plan
    nil
  end

  def current_plan
    nil
  end

  def feature_value(_feature_key)
    nil
  end

  def assign_plan(_plan, starts_at: Time.current)
    nil
  end

  # Retorna as features habilitadas (is_active: true) vinculadas à conta
  def enabled_features
    []
  end

  # Retorna todas as features vinculadas à conta
  def all_features
    []
  end

  # Retorna as features específicas da conta (account_features)
  def account_features_with_values
    []
  end

  # Retorna as features do plano ativo da conta
  def features_with_values
    []
  end

  # Retorna todas as features (plano + específicas da conta)
  def all_features_with_values
    []
  end

  # Retorna todas as features em formato hash, com cast de valor.
  def all_features_map
    {}
  end

  # Retorna apenas as chaves de features habilitadas (boolean true).
  def enabled_feature_keys
    []
  end

  def role_data
    account_users.find_by(account_id: id)&.role_data
  end

  # Método para validação de permissão no contexto da account
  # @param permission_key [String] A chave da permissão no formato "resource.action"
  # @param user [User] O usuário para verificar a permissão
  # @return [Boolean] true se o usuário tem permissão na account, false caso contrário
  def check_permission(permission_key, user)
    account_user = user.account_users.find_by(account: self)
    return false unless account_user

    account_user.has_permission?(permission_key)
  end

  private

  def notify_creation
    Rails.logger.info "Account created: #{name} (ID: #{id})"
  end

  def cast_feature_value(value)
    return value if value == true || value == false
    return false if value.nil?

    normalized_value = value.to_s.strip
    return true if normalized_value.casecmp("true").zero?
    return false if normalized_value.casecmp("false").zero?
    return normalized_value.to_i if normalized_value.match?(/\A-?\d+\z/)
    return normalized_value.to_f if normalized_value.match?(/\A-?\d+\.\d+\z/)

    normalized_value
  end
end
