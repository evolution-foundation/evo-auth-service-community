class AddKeycloakSubToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :keycloak_sub, :string
    add_index :users, :keycloak_sub, unique: true, where: "keycloak_sub IS NOT NULL"
  end
end
