# frozen_string_literal: true

# Read-only model for accessing admin-managed configuration from the shared
# `installation_configs` table (written by CRM).  Values whose key ends in
# `_SECRET` are Fernet-encrypted and decrypted transparently on read.
#
# This model intentionally has NO write callbacks — the auth service is a
# consumer, not a producer, of these configuration rows.
class InstallationConfig < ActiveRecord::Base
  self.table_name = 'installation_configs'

  CACHE_TTL = 60.seconds
  ENCRYPTION_KEY_DERIVATION_SALT = 'installation_config_encryption_v1'

  # ---------------------------------------------------------------------------
  # Encryption key resolution — must stay in sync with evo-ai-crm's
  # InstallationConfig so that values written by CRM can be decrypted here.
  # ---------------------------------------------------------------------------

  def self.encryption_key
    @encryption_key ||= resolve_encryption_key
  end

  def self.reset_encryption_key_cache!
    @encryption_key = nil
  end

  def self.resolve_encryption_key
    ENV['ENCRYPTION_KEY'].presence || derive_encryption_key_from_secret_key_base
  end

  def self.derive_encryption_key_from_secret_key_base
    secret = ENV['SECRET_KEY_BASE'].presence ||
             (defined?(Rails) && Rails.application&.secret_key_base.presence)
    raise 'ENCRYPTION_KEY or SECRET_KEY_BASE must be set' if secret.blank?

    key_material = ActiveSupport::KeyGenerator.new(secret).generate_key(
      ENCRYPTION_KEY_DERIVATION_SALT, 32
    )
    Base64.urlsafe_encode64(key_material)
  end

  # ---------------------------------------------------------------------------
  # Public read API
  # ---------------------------------------------------------------------------

  NOT_FOUND = :_installation_config_not_found
  private_constant :NOT_FOUND

  # Returns the plain (or decrypted) configuration value, with per-key caching.
  def self.get_value(key)
    cache_key = "installation_config:#{key}"

    cached = Rails.cache.read(cache_key)
    return (cached == NOT_FOUND ? nil : cached) unless cached.nil?

    record = find_by(name: key)
    unless record
      Rails.cache.write(cache_key, NOT_FOUND, expires_in: CACHE_TTL)
      return nil
    end

    val = record.value
    Rails.cache.write(cache_key, val, expires_in: CACHE_TTL)
    val
  rescue StandardError => e
    Rails.logger.warn("InstallationConfig.get_value(#{key}) failed: #{e.message}")
    nil
  end

  # Extracts and (if needed) decrypts the stored value.
  def value
    raw = read_raw_value
    return raw unless sensitive? && fernet_token?(raw)

    decrypt(raw)
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  def sensitive?
    name.to_s.end_with?('_SECRET')
  end

  private

  def read_raw_value
    sv = serialized_value
    return nil if sv.nil?

    # serialized_value is a JSONB column stored as { "value" => <actual> }
    if sv.is_a?(Hash)
      sv['value']
    else
      sv
    end
  end

  def fernet_token?(val)
    val.is_a?(String) && val.start_with?('gAAAAA')
  end

  def decrypt(token)
    require 'fernet'
    verifier = Fernet.verifier(self.class.encryption_key, token, enforce_ttl: false)
    verifier.valid? ? verifier.message : token
  rescue StandardError => e
    Rails.logger.warn("InstallationConfig decrypt failed for #{name}: #{e.message}")
    token
  end
end
