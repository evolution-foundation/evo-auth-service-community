# frozen_string_literal: true

class InitSchema < ActiveRecord::Migration[7.1]
  def up
    # These extensions must be enabled to support this database
    enable_extension "pg_stat_statements"
    enable_extension "pg_trgm"
    enable_extension "pgcrypto"
    enable_extension "plpgsql"
    enable_extension "uuid-ossp"

    # Access tokens table (managed by auth service)
    create_table :access_tokens, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :name, limit: 255, null: false
      t.string :owner_type
      t.string :scopes, null: false
      t.uuid :owner_id
      t.string :token
      t.timestamps default: -> { 'NOW()' }, null: false
    end
    add_index :access_tokens, [:owner_type, :owner_id], name: "index_access_tokens_on_owner_type_and_owner_id"
    add_index :access_tokens, :token, unique: true


    # Users table (managed by auth service)
    create_table :users, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :provider, default: "email", null: false
      t.string :uid, default: "", null: false
      t.string :encrypted_password, default: "", null: false
      t.string :reset_password_token
      t.datetime :reset_password_sent_at
      t.datetime :remember_created_at
      t.integer :sign_in_count, default: 0, null: false
      t.datetime :current_sign_in_at
      t.datetime :last_sign_in_at
      t.string :current_sign_in_ip
      t.string :last_sign_in_ip
      t.string :confirmation_token
      t.datetime :confirmed_at
      t.datetime :confirmation_sent_at
      t.string :unconfirmed_email
      t.string :name, null: false
      t.string :display_name
      t.string :email
      t.json :tokens
      t.string :pubsub_token
      t.integer :availability, default: 0
      t.jsonb :ui_settings, default: {}
      t.jsonb :custom_attributes, default: {}
      t.string :type
      t.text :message_signature
      t.string :otp_secret
      t.boolean :otp_required_for_login, default: false, null: false
      t.integer :consumed_timestep
      t.text :otp_backup_codes, array: true, default: []
      t.integer :mfa_method, default: 0, null: false
      t.string :email_otp_secret
      t.datetime :email_otp_sent_at
      t.integer :email_otp_attempts, default: 0
      t.datetime :mfa_confirmed_at
      t.datetime :last_mfa_failure_at
      t.integer :failed_mfa_attempts, default: 0
      t.timestamps default: -> { 'NOW()' }, null: false
    end
    add_index :users, :email
    add_index :users, :email_otp_sent_at
    add_index :users, :mfa_method
    add_index :users, :otp_required_for_login
    add_index :users, :pubsub_token, unique: true
    add_index :users, :reset_password_token, unique: true
    add_index :users, [:uid, :provider], unique: true


    # Active Storage tables (managed by auth service)
    create_table :active_storage_attachments, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :name, null: false
      t.string :record_type, null: false
      t.uuid :record_id, null: false
      t.uuid :blob_id, null: false
      t.datetime :created_at, null: false
    end
    add_index :active_storage_attachments, :blob_id
    add_index :active_storage_attachments, [:record_type, :record_id, :name, :blob_id], name: "index_active_storage_attachments_uniqueness", unique: true

    create_table :active_storage_blobs, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :key, null: false
      t.string :filename, null: false
      t.string :content_type
      t.text :metadata
      t.string :service_name, null: false
      t.bigint :byte_size, null: false
      t.string :checksum
      t.datetime :created_at, null: false
    end
    add_index :active_storage_blobs, :key, unique: true

    create_table :active_storage_variant_records, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :blob_id, null: false
      t.string :variation_digest, null: false
    end
    add_index :active_storage_variant_records, [:blob_id, :variation_digest], name: "index_active_storage_variant_records_uniqueness", unique: true

    # OAuth Applications (Doorkeeper)
    create_table :oauth_applications, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :name, null: false
      t.string :uid, null: false
      t.string :secret, null: false
      t.text :redirect_uri, null: false
      t.string :scopes, null: false, default: ''
      t.boolean :confidential, null: false, default: true
      t.boolean :trusted, default: false, null: false
      t.timestamps default: -> { 'NOW()' }, null: false
    end
    add_index :oauth_applications, :uid, unique: true

    # OAuth Access Grants (Doorkeeper)
    create_table :oauth_access_grants, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :resource_owner_id, null: false
      t.uuid :application_id, null: false
      t.string :token, null: false
      t.integer :expires_in, null: false
      t.text :redirect_uri, null: false
      t.string :scopes, null: false, default: ''
      t.datetime :created_at, null: false
      t.datetime :revoked_at
    end
    add_index :oauth_access_grants, :token, unique: true
    add_index :oauth_access_grants, :application_id
    add_index :oauth_access_grants, :resource_owner_id

    # OAuth Access Tokens (Doorkeeper)
    create_table :oauth_access_tokens, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :resource_owner_id
      t.uuid :application_id, null: false
      t.string :token, null: false
      t.string :refresh_token
      t.integer :expires_in
      t.string :scopes
      t.datetime :created_at, null: false
      t.datetime :revoked_at
      t.string :previous_refresh_token, null: false, default: ""
    end
    add_index :oauth_access_tokens, :token, unique: true
    add_index :oauth_access_tokens, :refresh_token, unique: true
    add_index :oauth_access_tokens, :application_id
    add_index :oauth_access_tokens, :resource_owner_id

    # Data Privacy Consents (GDPR/LGPD compliance)
    create_table :data_privacy_consents, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :user_id, null: false
      t.string :consent_type, null: false
      t.boolean :granted, default: false, null: false
      t.datetime :granted_at
      t.datetime :revoked_at
      t.string :ip_address
      t.text :user_agent
      t.jsonb :details, default: {}
      t.string :legal_basis
      t.text :purpose_description
      t.datetime :expires_at
      t.timestamps default: -> { 'NOW()' }, null: false
    end
    add_index :data_privacy_consents, [:user_id, :consent_type], unique: true
    add_index :data_privacy_consents, :user_id
    add_index :data_privacy_consents, :consent_type
    add_index :data_privacy_consents, :granted
    add_index :data_privacy_consents, :granted_at
    add_index :data_privacy_consents, :expires_at
    
    # RBAC + Bitmask
    create_table "roles", id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string "key", null: false
      t.string "name", null: false
      t.text "description"
      t.string  "type", limit: 10, null: false, default: "user"
      t.boolean "system", default: false, null: false
      t.timestamps default: -> { 'NOW()' }, null: false
      t.index ["key"], name: "index_roles_on_key", unique: true
      t.index ["type"], name: "index_roles_on_type"
      t.index ["type", "name"], name: "index_roles_on_type_and_name", unique: true
      t.index ["name"], name: "index_roles_on_name", unique: true
    end

    # RBAC + Bitmask
    create_table "role_permissions_actions", id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid "role_id", null: false
      t.string "permission_key", limit: 100, null: false
      t.timestamps default: -> { 'NOW()' }, null: false
      t.index ["role_id"], name: "index_role_permissions_actions_on_role_id"
      t.index ["permission_key"], name: "index_role_permissions_actions_on_permission_key"
      t.index ["role_id", "permission_key"], name: "index_role_perms_actions_unique", unique: true
    end

    # RBAC + Bitmask
    create_table "user_roles", id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid "user_id", null: false
      t.uuid "role_id", null: false
      t.uuid "granted_by_id"
      t.datetime "granted_at", default: -> { "CURRENT_TIMESTAMP" }
      t.timestamps default: -> { 'NOW()' }, null: false
      t.index ["granted_at"], name: "index_user_roles_on_granted_at"
      t.index ["granted_by_id"], name: "index_user_roles_on_granted_by_id"
      t.index ["role_id"], name: "index_user_roles_on_role_id"
      t.index ["user_id", "role_id"], name: "index_user_roles_unique", unique: true
      t.index ["user_id"], name: "index_user_roles_on_user_id"
    end

    # Foreign Keys
    add_foreign_key :active_storage_attachments, :active_storage_blobs, column: :blob_id
    add_foreign_key :active_storage_variant_records, :active_storage_blobs, column: :blob_id
    add_foreign_key :oauth_access_grants, :oauth_applications, column: :application_id
    add_foreign_key :oauth_access_tokens, :oauth_applications, column: :application_id
    add_foreign_key :role_permissions_actions, :roles, column: :role_id
    add_foreign_key :user_roles, :users, column: :user_id
    add_foreign_key :user_roles, :roles, column: :role_id
    add_foreign_key :user_roles, :users, column: :granted_by_id
    add_foreign_key :data_privacy_consents, :users
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "The initial migration is not revertable"
  end
end
