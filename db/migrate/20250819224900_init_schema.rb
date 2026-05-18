# frozen_string_literal: true

class InitSchema < ActiveRecord::Migration[7.1]
  # Idempotent on purpose. The filename timestamp was previously
  # `90250819224900` (year 9025 — historical typo) which sorted *after*
  # every real 2026-* migration, so on a fresh install Rails ran the 2026
  # migrations first and `create_user_tours` blew up with
  # `relation "users" does not exist`. The timestamp has been corrected to
  # `20250819224900` so init runs first.
  #
  # The migration stays robust to three scenarios:
  #
  # 1. Fresh install — runs first (after the timestamp fix) and creates
  #    every table the auth service owns.
  # 2. Fresh install where another service (eg. evo-core, Go) created its
  #    own copy of the `users` table directly via auto-migration before
  #    Rails got here. We don't want to crash with `PG::DuplicateTable`.
  # 3. Long-lived installs that already recorded the old `90250819224900`
  #    version. After the rename, Rails sees the new `20250819224900` as
  #    pending and re-runs it. Every DDL below is guarded with
  #    `if_not_exists: true` so the rerun is a no-op against an already
  #    initialised schema.
  #
  # Every `create_table`, `add_index` and `add_foreign_key` is therefore
  # wrapped in an existence check.
  def up
    # These extensions must be enabled to support this database
    enable_extension "pg_stat_statements"
    enable_extension "pg_trgm"
    enable_extension "pgcrypto"
    enable_extension "plpgsql"
    enable_extension "uuid-ossp"

    # Access tokens table (managed by auth service)
    create_table :access_tokens, id: :uuid, default: -> { "gen_random_uuid()" }, if_not_exists: true do |t|
      t.string :name, limit: 255, null: false
      t.string :owner_type
      t.string :scopes, null: false
      t.uuid :owner_id
      t.string :token
      t.timestamps default: -> { 'NOW()' }, null: false
    end
    add_index :access_tokens, [:owner_type, :owner_id], name: "index_access_tokens_on_owner_type_and_owner_id", if_not_exists: true
    add_index :access_tokens, :token, unique: true, if_not_exists: true


    # Users table (managed by auth service)
    create_table :users, id: :uuid, default: -> { "gen_random_uuid()" }, if_not_exists: true do |t|
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
    add_index :users, :email, if_not_exists: true
    add_index :users, :email_otp_sent_at, if_not_exists: true
    add_index :users, :mfa_method, if_not_exists: true
    add_index :users, :otp_required_for_login, if_not_exists: true
    add_index :users, :pubsub_token, unique: true, if_not_exists: true
    add_index :users, :reset_password_token, unique: true, if_not_exists: true
    add_index :users, [:uid, :provider], unique: true, if_not_exists: true


    # Active Storage tables (managed by auth service)
    create_table :active_storage_attachments, id: :uuid, default: -> { "gen_random_uuid()" }, if_not_exists: true do |t|
      t.string :name, null: false
      t.string :record_type, null: false
      t.uuid :record_id, null: false
      t.uuid :blob_id, null: false
      t.datetime :created_at, null: false
    end
    add_index :active_storage_attachments, :blob_id, if_not_exists: true
    add_index :active_storage_attachments, [:record_type, :record_id, :name, :blob_id], name: "index_active_storage_attachments_uniqueness", unique: true, if_not_exists: true

    create_table :active_storage_blobs, id: :uuid, default: -> { "gen_random_uuid()" }, if_not_exists: true do |t|
      t.string :key, null: false
      t.string :filename, null: false
      t.string :content_type
      t.text :metadata
      t.string :service_name, null: false
      t.bigint :byte_size, null: false
      t.string :checksum
      t.datetime :created_at, null: false
    end
    add_index :active_storage_blobs, :key, unique: true, if_not_exists: true

    create_table :active_storage_variant_records, id: :uuid, default: -> { "gen_random_uuid()" }, if_not_exists: true do |t|
      t.uuid :blob_id, null: false
      t.string :variation_digest, null: false
    end
    add_index :active_storage_variant_records, [:blob_id, :variation_digest], name: "index_active_storage_variant_records_uniqueness", unique: true, if_not_exists: true

    # OAuth Applications (Doorkeeper)
    create_table :oauth_applications, id: :uuid, default: -> { "gen_random_uuid()" }, if_not_exists: true do |t|
      t.string :name, null: false
      t.string :uid, null: false
      t.string :secret, null: false
      t.text :redirect_uri, null: false
      t.string :scopes, null: false, default: ''
      t.boolean :confidential, null: false, default: true
      t.boolean :trusted, default: false, null: false
      t.timestamps default: -> { 'NOW()' }, null: false
    end
    add_index :oauth_applications, :uid, unique: true, if_not_exists: true

    # OAuth Access Grants (Doorkeeper)
    create_table :oauth_access_grants, id: :uuid, default: -> { "gen_random_uuid()" }, if_not_exists: true do |t|
      t.uuid :resource_owner_id, null: false
      t.uuid :application_id, null: false
      t.string :token, null: false
      t.integer :expires_in, null: false
      t.text :redirect_uri, null: false
      t.string :scopes, null: false, default: ''
      t.datetime :created_at, null: false
      t.datetime :revoked_at
    end
    add_index :oauth_access_grants, :token, unique: true, if_not_exists: true
    add_index :oauth_access_grants, :application_id, if_not_exists: true
    add_index :oauth_access_grants, :resource_owner_id, if_not_exists: true

    # OAuth Access Tokens (Doorkeeper)
    create_table :oauth_access_tokens, id: :uuid, default: -> { "gen_random_uuid()" }, if_not_exists: true do |t|
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
    add_index :oauth_access_tokens, :token, unique: true, if_not_exists: true
    add_index :oauth_access_tokens, :refresh_token, unique: true, if_not_exists: true
    add_index :oauth_access_tokens, :application_id, if_not_exists: true
    add_index :oauth_access_tokens, :resource_owner_id, if_not_exists: true

    # Data Privacy Consents (GDPR/LGPD compliance)
    create_table :data_privacy_consents, id: :uuid, default: -> { "gen_random_uuid()" }, if_not_exists: true do |t|
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
    add_index :data_privacy_consents, [:user_id, :consent_type], unique: true, if_not_exists: true
    add_index :data_privacy_consents, :user_id, if_not_exists: true
    add_index :data_privacy_consents, :consent_type, if_not_exists: true
    add_index :data_privacy_consents, :granted, if_not_exists: true
    add_index :data_privacy_consents, :granted_at, if_not_exists: true
    add_index :data_privacy_consents, :expires_at, if_not_exists: true

    # RBAC + Bitmask. Inline t.index calls inside create_table do not
    # support if_not_exists, so we omit them here and add the indexes
    # explicitly afterwards with the guard.
    create_table "roles", id: :uuid, default: -> { "gen_random_uuid()" }, if_not_exists: true do |t|
      t.string "key", null: false
      t.string "name", null: false
      t.text "description"
      t.string  "type", limit: 10, null: false, default: "user"
      t.boolean "system", default: false, null: false
      t.timestamps default: -> { 'NOW()' }, null: false
    end
    add_index :roles, :key, name: "index_roles_on_key", unique: true, if_not_exists: true
    add_index :roles, :type, name: "index_roles_on_type", if_not_exists: true
    add_index :roles, [:type, :name], name: "index_roles_on_type_and_name", unique: true, if_not_exists: true
    add_index :roles, :name, name: "index_roles_on_name", unique: true, if_not_exists: true

    # RBAC + Bitmask
    create_table "role_permissions_actions", id: :uuid, default: -> { "gen_random_uuid()" }, if_not_exists: true do |t|
      t.uuid "role_id", null: false
      t.string "permission_key", limit: 100, null: false
      t.timestamps default: -> { 'NOW()' }, null: false
    end
    add_index :role_permissions_actions, :role_id, name: "index_role_permissions_actions_on_role_id", if_not_exists: true
    add_index :role_permissions_actions, :permission_key, name: "index_role_permissions_actions_on_permission_key", if_not_exists: true
    add_index :role_permissions_actions, [:role_id, :permission_key], name: "index_role_perms_actions_unique", unique: true, if_not_exists: true

    # RBAC + Bitmask
    create_table "user_roles", id: :uuid, default: -> { "gen_random_uuid()" }, if_not_exists: true do |t|
      t.uuid "user_id", null: false
      t.uuid "role_id", null: false
      t.uuid "granted_by_id"
      t.datetime "granted_at", default: -> { "CURRENT_TIMESTAMP" }
      t.timestamps default: -> { 'NOW()' }, null: false
    end
    add_index :user_roles, :granted_at, name: "index_user_roles_on_granted_at", if_not_exists: true
    add_index :user_roles, :granted_by_id, name: "index_user_roles_on_granted_by_id", if_not_exists: true
    add_index :user_roles, :role_id, name: "index_user_roles_on_role_id", if_not_exists: true
    add_index :user_roles, [:user_id, :role_id], name: "index_user_roles_unique", unique: true, if_not_exists: true
    add_index :user_roles, :user_id, name: "index_user_roles_on_user_id", if_not_exists: true

    # Foreign Keys — `add_foreign_key` doesn't support `if_not_exists`
    # before Rails 7.2, so we check explicitly. Each guard is keyed by
    # (from_table, column, to_table) so we stay correct even if multiple
    # FKs target the same parent table.
    add_fk_if_missing :active_storage_attachments, :active_storage_blobs, :blob_id
    add_fk_if_missing :active_storage_variant_records, :active_storage_blobs, :blob_id
    add_fk_if_missing :oauth_access_grants, :oauth_applications, :application_id
    add_fk_if_missing :oauth_access_tokens, :oauth_applications, :application_id
    add_fk_if_missing :role_permissions_actions, :roles, :role_id
    add_fk_if_missing :user_roles, :users, :user_id
    add_fk_if_missing :user_roles, :roles, :role_id
    add_fk_if_missing :user_roles, :users, :granted_by_id
    add_fk_if_missing :data_privacy_consents, :users, :user_id
  end

  private

  def add_fk_if_missing(from_table, to_table, column)
    return if foreign_key_exists?(from_table, to_table, column: column)

    add_foreign_key from_table, to_table, column: column
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "The initial migration is not revertable"
  end
end
