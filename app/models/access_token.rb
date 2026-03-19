# == Schema Information
#
# Table name: access_tokens
#
#  id         :uuid           not null, primary key
#  name       :string
#  owner_type :string
#  token      :string
#  scopes     :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  owner_id   :uuid
#  issued_id  :uuid
#

class AccessToken < ApplicationRecord
  belongs_to :owner, polymorphic: true
  belongs_to :issued_by, class_name: 'User', foreign_key: 'issued_id', optional: true

  validates :token, presence: true, uniqueness: true
  validates :scopes, presence: true
  validates :name, presence: true
  validates :owner_type, inclusion: { in: %w[Account User] }
  validates :issued_id, presence: true, if: -> { owner_type == 'Account' }

  before_validation :generate_token, on: :create
  before_validation :set_owner_type, on: :create
  
  def self.generate_unique_token
    loop do
      token = SecureRandom.hex(32)
      break token unless exists?(token: token)
    end
  end

  def update_token
    self.token = self.class.generate_unique_token
    save!
  end

  # Verifica se o token tem permissão específica baseada nos scopes
  # @param permission_key [String] A chave da permissão no formato "resource.action"
  # @return [Boolean] true se o token tem a permissão nos scopes, false caso contrário
  def has_scope?(permission_key)
    return false if scopes.blank?
    
    # Parse scopes - assumindo que são separados por espaço ou vírgula
    token_scopes = scopes.split(/[,\s]+/).map(&:strip).reject(&:blank?)
    
    # Verificar se a permissão específica está nos scopes
    token_scopes.include?(permission_key)
  end

  private

  def generate_token
    self.token = self.class.generate_unique_token if token.blank?
  end

  def set_owner_type
    self.owner_type = owner.class.name if owner && owner_type.blank?
  end
end
