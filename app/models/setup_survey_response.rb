# frozen_string_literal: true

# == Schema Information
#
# Table name: setup_survey_responses
#
#  id                :uuid             not null, primary key
#  user_id           :uuid             not null
#  team_size         :string
#  daily_volume      :string
#  main_channel      :string
#  main_channel_other :string
#  uses_ai           :string
#  biggest_pain      :string
#  crm_experience    :string
#  main_goal         :string
#  onboarding_pushed_at :datetime
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#
class SetupSurveyResponse < ApplicationRecord
  belongs_to :user

  validates :user_id, uniqueness: true
end
