# frozen_string_literal: true

class CreateRuntimeConfigs < ActiveRecord::Migration[7.1]
  def change
    create_table :runtime_configs do |t|
      t.string :key,   null: false
      t.text   :value, null: false, default: ''
      t.timestamps
    end

    add_index :runtime_configs, :key, unique: true
  end
end
