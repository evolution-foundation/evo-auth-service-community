class AddIssuedIdToAccessTokens < ActiveRecord::Migration[7.1]
  # Idempotent: long-lived installs may already have :issued_id on
  # access_tokens (it was part of the original schema before this migration
  # was added). See 20250819224900_init_schema.rb for the broader context.
  def change
    unless column_exists?(:access_tokens, :issued_id)
      add_column :access_tokens, :issued_id, :uuid, if_not_exists: true
    end

    unless foreign_key_exists?(:access_tokens, :users, column: :issued_id)
      add_foreign_key :access_tokens, :users, column: :issued_id, if_not_exists: true
    end

    unless index_exists?(:access_tokens, :issued_id)
      add_index :access_tokens, :issued_id, if_not_exists: true
    end
  end
end
