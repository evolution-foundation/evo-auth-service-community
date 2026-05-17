# frozen_string_literal: true

class CreateUserTours < ActiveRecord::Migration[7.1]
  def change
    # Idempotent: user_tours was previously added directly to db/schema.rb
    # without a migration file (commit 00f5d75). Production databases
    # bootstrapped from that schema already have the table. Make this
    # migration safe to re-run.
    create_table :user_tours, id: :uuid, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string :tour_key, null: false
      t.datetime :completed_at, null: false

      t.timestamps
    end

    add_index :user_tours, [:user_id, :tour_key], unique: true, if_not_exists: true
  end
end
