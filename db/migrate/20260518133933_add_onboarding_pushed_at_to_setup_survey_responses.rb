# frozen_string_literal: true

class AddOnboardingPushedAtToSetupSurveyResponses < ActiveRecord::Migration[7.1]
  def change
    add_column :setup_survey_responses, :onboarding_pushed_at, :datetime
  end
end
