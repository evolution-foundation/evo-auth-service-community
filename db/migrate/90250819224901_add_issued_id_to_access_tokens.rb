class AddIssuedIdToAccessTokens < ActiveRecord::Migration[7.1]
  def change
    add_column :access_tokens, :issued_id, :uuid
    add_foreign_key :access_tokens, :users, column: :issued_id
    add_index :access_tokens, :issued_id

    # Backfill existing Account tokens with the first user from the account
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE access_tokens
          SET issued_id = (
            SELECT account_users.user_id
            FROM account_users
            WHERE account_users.account_id = access_tokens.owner_id
            ORDER BY account_users.created_at ASC
            LIMIT 1
          )
          WHERE owner_type = 'Account' AND issued_id IS NULL;
        SQL
        
        # Add check constraint: issued_id cannot be null when owner_type is 'Account'
        execute <<-SQL
          ALTER TABLE access_tokens
          ADD CONSTRAINT check_issued_id_for_account
          CHECK (
            (owner_type != 'Account') OR (owner_type = 'Account' AND issued_id IS NOT NULL)
          );
        SQL
      end

      dir.down do
        execute <<-SQL
          ALTER TABLE access_tokens
          DROP CONSTRAINT IF EXISTS check_issued_id_for_account;
        SQL
      end
    end
  end
end
