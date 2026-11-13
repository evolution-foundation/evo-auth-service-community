# == Schema Information
#
# Table name: access_tokens
#
#  id         :uuid           not null, primary key
#  name       :string
#  owner_type :string
#  token      :string           SHA-256 of the value
#  scopes     :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  owner_id   :uuid
#  issued_id  :uuid
#

class AccessToken < ApplicationRecord
  # Legacy tokens (and the one MFA login issues) carry this scope and keep the
  # owner's full permissions. Any other scope list restricts the token to it.
  UNRESTRICTED_SCOPE = 'default'

  belongs_to :owner, polymorphic: true
  belongs_to :issued_by, class_name: 'User', foreign_key: 'issued_id', optional: true

  validates :token, presence: true, uniqueness: true
  validates :scopes, presence: true
  validates :name, presence: true
  validates :owner_type, inclusion: { in: %w[Account User] }
  validates :issued_id, presence: true, if: -> { owner_type == 'Account' }

  before_validation :generate_token, on: :create
  before_validation :set_owner_type, on: :create

  def self.digest(raw_token)
    Digest::SHA256.hexdigest(raw_token.to_s)
  end

  def self.for_token(raw_token)
    return nil if raw_token.blank?

    find_by(token: digest(raw_token)) || hash_stored_value(raw_token)
  end

  # A token stored before hashing still holds its value: it is hashed on use.
  def self.hash_stored_value(raw_token)
    record = find_by(token: raw_token.to_s)
    record&.update_column(:token, digest(raw_token)) # rubocop:disable Rails/SkipsModelValidations
    record
  end

  def self.generate_unique_token
    loop do
      token = SecureRandom.hex(32)
      break token unless exists?(token: digest(token))
    end
  end

  def update_token
    previous_digest = self[:token]
    assign_token(self.class.generate_unique_token)
    save!
    TokenValidationService.invalidate_cache_for_digest(previous_digest)
    true
  end

  # The value on the instance that generated it (create / update_token), so the
  # API can show it once; the stored hash otherwise.
  def token
    @raw_token || super
  end

  def scope_list
    scopes.to_s.split(/[,\s]+/).map(&:strip).reject(&:blank?)
  end

  def unrestricted?
    scope_list.include?(UNRESTRICTED_SCOPE)
  end

  # Permission keys the token may exercise, mirroring User#has_permission?: the
  # scopes themselves, the reads every user holds and what the scopes imply.
  # Empty for an unrestricted token, which is bounded by the owner alone.
  def effective_scopes
    return [] if unrestricted?

    keys = scope_list
    implied = User::OPERATIONAL_IMPLICATIONS.flat_map { |source, targets| keys.include?(source) ? targets : [] }
    (keys + User::BASIC_READ_PERMISSIONS + implied).uniq
  end

  # @param permission_key [String] "resource.action"
  def has_scope?(permission_key)
    return false if permission_key.blank?
    return true if unrestricted?

    effective_scopes.include?(permission_key)
  end

  private

  def generate_token
    assign_token(self.class.generate_unique_token) if self[:token].blank?
  end

  def assign_token(raw_token)
    @raw_token = raw_token
    self[:token] = self.class.digest(raw_token)
  end

  def set_owner_type
    self.owner_type = owner.class.name if owner && owner_type.blank?
  end
end
