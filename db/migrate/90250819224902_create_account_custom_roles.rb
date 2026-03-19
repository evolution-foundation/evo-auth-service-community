class CreateAccountCustomRoles < ActiveRecord::Migration[7.1]
  def change
    # =====================================================
    # 1. ACCOUNT CUSTOM ROLES (tabela principal)
    # =====================================================
    return if table_exists?(:account_custom_roles)

    create_table :account_custom_roles, id: :uuid do |t|
      t.uuid :account_id, null: false

      # Identificação
      t.string :key, limit: 100, null: false
      t.string :name, limit: 255, null: false
      t.text :description

      # Metadata
      t.boolean :is_active, default: true, null: false
      t.uuid :created_by_id
      t.uuid :updated_by_id

      t.timestamps default: -> { 'now()' }, null: false
    end

    # Índices para account_custom_roles
    add_index :account_custom_roles, :account_id
    add_index :account_custom_roles, [:account_id, :key], unique: true, name: 'index_custom_roles_on_account_and_key'
    add_index :account_custom_roles, [:account_id, :name], unique: true, name: 'index_custom_roles_on_account_and_name'
    add_index :account_custom_roles, [:account_id, :is_active], name: 'index_custom_roles_on_account_and_active'

    # Foreign keys
    add_foreign_key :account_custom_roles, :accounts, on_delete: :cascade
    add_foreign_key :account_custom_roles, :users, column: :created_by_id, on_delete: :nullify
    add_foreign_key :account_custom_roles, :users, column: :updated_by_id, on_delete: :nullify

    # =====================================================
    # 2. RESOURCE-LEVEL PERMISSIONS (formato resource.action)
    # =====================================================
    create_table :account_custom_role_permissions, id: :uuid do |t|
      t.uuid :account_custom_role_id, null: false
      t.uuid :account_id, null: false

      # Permission no formato 'resource.action' (ex: 'contacts.read')
      t.string :permission_key, limit: 100, null: false

      t.timestamps default: -> { 'now()' }, null: false
    end

    # Índices para account_custom_role_permissions
    add_index :account_custom_role_permissions, :account_custom_role_id
    add_index :account_custom_role_permissions, :account_id
    add_index :account_custom_role_permissions, :permission_key
    add_index :account_custom_role_permissions, [:account_custom_role_id, :permission_key],
              unique: true, name: 'index_custom_role_perms_unique'

    # Foreign keys
    add_foreign_key :account_custom_role_permissions, :account_custom_roles,
                    column: :account_custom_role_id, on_delete: :cascade
    add_foreign_key :account_custom_role_permissions, :accounts, on_delete: :cascade

    # =====================================================
    # 3. INSTANCE-LEVEL PERMISSIONS (resource específico)
    # =====================================================
    create_table :account_custom_role_resource_scopes, id: :uuid do |t|
      t.uuid :account_custom_role_id, null: false
      t.uuid :account_id, null: false

      # Identificação do recurso
      t.string :resource_type, limit: 100, null: false  # 'Pipeline', 'Contact', 'Label'
      t.uuid :resource_id, null: false                  # ID do recurso específico

      # Ações permitidas: ["read", "update"] ou ["*"] para todas
      t.jsonb :actions, null: false, default: []

      # Metadata
      t.uuid :created_by_id

      t.timestamps default: -> { 'now()' }, null: false
    end

    # Índices para account_custom_role_resource_scopes
    add_index :account_custom_role_resource_scopes, :account_custom_role_id
    add_index :account_custom_role_resource_scopes, :account_id
    add_index :account_custom_role_resource_scopes, [:resource_type, :resource_id],
              name: 'index_custom_role_scopes_on_resource'
    add_index :account_custom_role_resource_scopes, :actions, using: :gin
    add_index :account_custom_role_resource_scopes,
              [:account_custom_role_id, :account_id, :resource_type, :resource_id],
              unique: true, name: 'index_custom_role_scopes_unique'

    # Foreign keys
    add_foreign_key :account_custom_role_resource_scopes, :account_custom_roles,
                    column: :account_custom_role_id, on_delete: :cascade
    add_foreign_key :account_custom_role_resource_scopes, :accounts, on_delete: :cascade
    add_foreign_key :account_custom_role_resource_scopes, :users,
                    column: :created_by_id, on_delete: :nullify

    # =====================================================
    # 4. ATUALIZAR ACCOUNT_USERS (adicionar account_custom_role_id)
    # =====================================================
    add_column :account_users, :account_custom_role_id, :uuid
    add_index :account_users, :account_custom_role_id
    add_foreign_key :account_users, :account_custom_roles,
                    column: :account_custom_role_id, on_delete: :nullify

    # Constraint: usuário pode ter role_id (system) OU account_custom_role_id (custom), não ambos
    # Permitir ambos null para migração gradual
    add_check_constraint :account_users,
                        'NOT (role_id IS NOT NULL AND account_custom_role_id IS NOT NULL)',
                        name: 'check_not_both_roles'
  end
end
