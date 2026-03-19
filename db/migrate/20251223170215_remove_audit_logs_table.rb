# frozen_string_literal: true

class RemoveAuditLogsTable < ActiveRecord::Migration[7.1]
  def up
    # Remove foreign keys first
    remove_foreign_key :audit_logs, :users if foreign_key_exists?(:audit_logs, :users)
    remove_foreign_key :audit_logs, :accounts if foreign_key_exists?(:audit_logs, :accounts)
    
    # Remove indexes
    remove_index :audit_logs, :action if index_exists?(:audit_logs, :action)
    remove_index :audit_logs, :created_at if index_exists?(:audit_logs, :created_at)
    remove_index :audit_logs, [:user_id, :created_at] if index_exists?(:audit_logs, [:user_id, :created_at])
    remove_index :audit_logs, [:account_id, :created_at] if index_exists?(:audit_logs, [:account_id, :created_at])
    remove_index :audit_logs, [:resource_type, :resource_id] if index_exists?(:audit_logs, [:resource_type, :resource_id])
    remove_index :audit_logs, :success if index_exists?(:audit_logs, :success)
    remove_index :audit_logs, :severity if index_exists?(:audit_logs, :severity)
    remove_index :audit_logs, :ip_address if index_exists?(:audit_logs, :ip_address)
    remove_index :audit_logs, :details if index_exists?(:audit_logs, :details)
    
    # Drop table
    drop_table :audit_logs if table_exists?(:audit_logs)
  end

  def down
    # Recreate table (if needed for rollback)
    create_table :audit_logs, id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
      t.uuid :user_id, null: true
      t.uuid :account_id, null: true
      t.string :action, null: false
      t.string :resource_type
      t.uuid :resource_id
      t.jsonb :details, default: {}
      t.string :ip_address
      t.text :user_agent
      t.boolean :success, default: true, null: false
      t.string :session_id
      t.string :request_id
      t.integer :severity, default: 0, null: false
      t.timestamps default: -> { 'NOW()' }, null: false
    end
    
    add_index :audit_logs, :action
    add_index :audit_logs, :created_at
    add_index :audit_logs, [:user_id, :created_at]
    add_index :audit_logs, [:account_id, :created_at]
    add_index :audit_logs, [:resource_type, :resource_id]
    add_index :audit_logs, :success
    add_index :audit_logs, :severity
    add_index :audit_logs, :ip_address
    add_index :audit_logs, :details, using: :gin
    
    add_foreign_key :audit_logs, :users
    add_foreign_key :audit_logs, :accounts
  end
end

