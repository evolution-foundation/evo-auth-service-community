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
    key = ENV.fetch('ENCRYPTION_KEY') { raise 'ENCRYPTION_KEY required for decryption' }
    verifier = Fernet.verifier(key, token, enforce_ttl: false)
    verifier.valid? ? verifier.message : token
  rescue StandardError => e
    Rails.logger.warn("InstallationConfig decrypt failed for #{name}: #{e.message}")
    token
  end
end
