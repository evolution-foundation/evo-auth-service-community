class AddStatusToUserTours < ActiveRecord::Migration[7.1]
  def change
    add_column :user_tours, :status, :string, null: false, default: 'completed'
  end
end
