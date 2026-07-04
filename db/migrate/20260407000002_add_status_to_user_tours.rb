class AddStatusToUserTours < ActiveRecord::Migration[7.1]
  def change
    # Idempotent: column may already exist on databases bootstrapped from
    # schema.rb directly (commit 00f5d75 included :status). See
    # 20260407000001_create_user_tours.rb for context.
    return if column_exists?(:user_tours, :status)

    add_column :user_tours, :status, :string, null: false, default: 'completed', if_not_exists: true
  end
end
