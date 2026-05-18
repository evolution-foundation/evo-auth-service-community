# frozen_string_literal: true

module Licensing
  # Pushes a setup survey response to the licensing server.
  #
  # Idempotent: skips when the runtime is not active yet, when the survey
  # is missing, or when onboarding_pushed_at is already set. Fired from
  # both /setup/activate (when survey already exists) and from the survey
  # save endpoints (when activation already happened) — whichever lands
  # second is the one that actually performs the push.
  class PushOnboardingSurveyJob < ApplicationJob
    queue_as :licensing

    retry_on Transport::NetworkError,  wait: :polynomially_longer, attempts: 5
    retry_on Transport::ResponseError, wait: :polynomially_longer, attempts: 5

    def perform(survey_id)
      survey = SetupSurveyResponse.find_by(id: survey_id)
      return if survey.nil?
      return if survey.onboarding_pushed_at.present?

      ctx = Runtime.context
      return unless ctx&.active?

      pushed = Onboarding.push_survey(survey: survey, ctx: ctx)
      survey.update_column(:onboarding_pushed_at, Time.current) if pushed
    end
  end
end
