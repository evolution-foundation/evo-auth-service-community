# frozen_string_literal: true

class CreateRuntimeConfigs < ActiveRecord::Migration[7.1]
  def change
    create_table :runtime_configs, if_not_exists: true do |t|
      t.string :key,   null: false
      t.text   :value, null: false, default: ''
      t.timestamps
    end

    add_index :runtime_configs, :key, unique: true, if_not_exists: true
  end
end
