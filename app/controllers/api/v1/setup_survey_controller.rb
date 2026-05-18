# frozen_string_literal: true

# Authenticated endpoint for saving/checking the onboarding survey.
# Used when the user logs in before completing the survey (e.g. survey_token expired).
class Api::V1::SetupSurveyController < Api::BaseController
  # GET /api/v1/setup_survey
  def show
    success_response(
      data: { completed: current_user.setup_survey_completed? },
      message: 'Survey status retrieved successfully'
    )
  end

  # POST /api/v1/setup_survey
  def create
    survey = current_user.setup_survey_response || current_user.build_setup_survey_response
    survey.assign_attributes(survey_params)

    if survey.save
      Licensing::PushOnboardingSurveyJob.perform_later(survey.id)
      success_response(data: { completed: true }, message: 'Survey saved successfully')
    else
      render_unprocessable_entity(survey.errors)
    end
  end

  private

  def survey_params
    params.permit(:team_size, :daily_volume, :main_channel, :main_channel_other,
                  :uses_ai, :biggest_pain, :crm_experience, :main_goal)
  end
end
