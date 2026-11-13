# == Schema Information
#
# Table name: access_tokens
#
#  id         :uuid           not null, primary key
#  name       :string
#  owner_type :string
#  token      :string           (ignored; cleared by HashAccessTokens)
#  token_digest :string
#  scopes     :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  owner_id   :uuid
#  issued_id  :uuid
#

class AccessToken < ApplicationRecord
  # Only the SHA-256 digest is kept. The raw value exists in memory on the
  # instance that generated it (create / update_token), so the API can show it
  # once; a token read back from the database has no value. The legacy `token`
  # column is read only to migrate rows written before the digest existed.
  self.ignored_columns += ['token']

  # Legacy tokens (and the one MFA login issues) carry this scope and keep the
  # owner's full permissions. Any other scope list restricts the token to it.
  UNRESTRICTED_SCOPE = 'default'

  belongs_to :owner, polymorphic: true
  belongs_to :issued_by, class_name: 'User', foreign_key: 'issued_id', optional: true

  attr_reader :token

  validates :token_digest, presence: true, uniqueness: true
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

    find_by(token_digest: digest(raw_token)) || migrate_stored_value(raw_token)
  end

  # A row still holding its value (written by an instance of the previous
  # release during a rolling deploy) gets its digest and loses the value on use.
  def self.migrate_stored_value(raw_token)
    record = where(token_digest: nil).find_by('token = ?', raw_token.to_s)
    return nil unless record

    where(id: record.id).update_all(token_digest: digest(raw_token), token: nil) # rubocop:disable Rails/SkipsModelValidations
    record.reload
  end

  # Fills missing digests and clears every stored value; returns how many rows
  # still held one.
  def self.backfill_and_clear_values
    connection.update(<<~SQL.squish)
      UPDATE access_tokens
      SET token_digest = COALESCE(token_digest, encode(sha256(convert_to(token, 'UTF8')), 'hex')),
          token = NULL
      WHERE token IS NOT NULL
    SQL
  end

  def self.generate_unique_token
    loop do
      token = SecureRandom.hex(32)
      break token unless exists?(token_digest: digest(token))
    end
  end

  def update_token
    previous_digest = token_digest
    assign_token(self.class.generate_unique_token)
    save!
    TokenValidationService.invalidate_cache_for_digest(previous_digest)
    true
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
    assign_token(self.class.generate_unique_token) if token_digest.blank?
  end

  def assign_token(raw_token)
    @token = raw_token
    self.token_digest = self.class.digest(raw_token)
  end

  def set_owner_type
    self.owner_type = owner.class.name if owner && owner_type.blank?
  end
end
