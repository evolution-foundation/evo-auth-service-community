# frozen_string_literal: true

module Licensing
  # Pushes the post-bootstrap onboarding survey to the licensing server.
  # The licensing server links it to the customer behind the active api_key.
  module Onboarding
    SURVEY_VERSION = 'v1'

    # Returns true on a successful push.
    # Returns false only when there is nothing to do (no runtime, no survey).
    # Transport failures are re-raised so ActiveJob `retry_on` can back off.
    def self.push_survey(survey:, ctx: Runtime.context)
      return false unless ctx&.active?
      return false if survey.nil?

      transport = Transport.new(base_url: Endpoint.resolve_url, api_key: ctx.api_key)
      transport.post_signed('/v1/customers/onboarding', {
        team_size:          survey.team_size,
        daily_volume:       survey.daily_volume,
        main_channel:       survey.main_channel,
        main_channel_other: survey.main_channel_other,
        uses_ai:            survey.uses_ai,
        biggest_pain:       survey.biggest_pain,
        crm_experience:     survey.crm_experience,
        main_goal:          survey.main_goal,
        survey_version:     SURVEY_VERSION
      })

      true
    end
  end
end
