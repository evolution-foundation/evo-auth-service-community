# frozen_string_literal: true

class AddKeycloakRefreshTokenToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :keycloak_refresh_token, :text
    add_column :users, :keycloak_refresh_token_expires_at, :datetime
  end
end
