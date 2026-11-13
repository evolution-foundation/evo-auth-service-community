# frozen_string_literal: true

# API access tokens are looked up by their SHA-256 digest, and the raw value is
# no longer stored. Existing tokens keep working: their digest is computed from
# the stored value before the value is cleared. The `token` column stays (empty)
# so services that still map it keep booting; dropping it is a later migration.
# Irreversible on purpose: the cleared values cannot be recovered.
class HashAccessTokens < ActiveRecord::Migration[7.1]
  def up
    add_column :access_tokens, :token_digest, :string

    execute <<~SQL.squish
      UPDATE access_tokens
      SET token_digest = encode(sha256(convert_to(token, 'UTF8')), 'hex')
      WHERE token IS NOT NULL AND token_digest IS NULL
    SQL

    add_index :access_tokens, :token_digest, unique: true
    execute 'UPDATE access_tokens SET token = NULL'
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
