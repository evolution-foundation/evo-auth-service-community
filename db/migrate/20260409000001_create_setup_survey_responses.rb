# frozen_string_literal: true

class CreateSetupSurveyResponses < ActiveRecord::Migration[7.1]
  def change
    # Idempotent: safe to re-run if any previous attempt partially created
    # the table (e.g., on a schema drift between staging/prod).
    create_table :setup_survey_responses, id: :uuid, if_not_exists: true do |t|
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
