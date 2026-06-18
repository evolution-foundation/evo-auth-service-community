class AddKeycloakIdTokenToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :keycloak_id_token, :text
  end
end
