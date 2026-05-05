# frozen_string_literal: true

class CreateSetupSurveyResponses < ActiveRecord::Migration[7.1]
  def change
    create_table :setup_survey_responses, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid, index: { unique: true }
      t.string :team_size
      t.string :daily_volume
      t.string :main_channel
      t.string :main_channel_other
      t.string :uses_ai
      t.string :biggest_pain
      t.string :crm_experience
      t.string :main_goal
      t.timestamps
    end
  end
end
