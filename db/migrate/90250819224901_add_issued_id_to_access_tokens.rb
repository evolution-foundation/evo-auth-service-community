class AddIssuedIdToAccessTokens < ActiveRecord::Migration[7.1]
  def change
    add_column :access_tokens, :issued_id, :uuid
    add_foreign_key :access_tokens, :users, column: :issued_id
    add_index :access_tokens, :issued_id
  end
end
