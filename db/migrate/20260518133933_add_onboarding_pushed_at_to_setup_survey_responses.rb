# frozen_string_literal: true

class AddOnboardingPushedAtToSetupSurveyResponses < ActiveRecord::Migration[7.1]
  def change
    return if column_exists?(:setup_survey_responses, :onboarding_pushed_at)

    add_column :setup_survey_responses, :onboarding_pushed_at, :datetime
  end
end
