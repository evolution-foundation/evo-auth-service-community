# frozen_string_literal: true

# API access tokens are looked up by their SHA-256 digest. This backfills the
# digest of existing tokens and leaves their stored value alone, so instances
# still running the previous release keep authenticating them during a rolling
# deploy. Once every instance runs this release, `rails access_tokens:clear_values`
# clears the stored values; a token used before that is cleared on first use.
class HashAccessTokens < ActiveRecord::Migration[7.1]
  def up
    add_column :access_tokens, :token_digest, :string

    execute <<~SQL.squish
      UPDATE access_tokens
      SET token_digest = encode(sha256(convert_to(token, 'UTF8')), 'hex')
      WHERE token IS NOT NULL AND token_digest IS NULL
    SQL

    add_index :access_tokens, :token_digest, unique: true
  end

  def down
    remove_index :access_tokens, :token_digest
    remove_column :access_tokens, :token_digest
  end
end
