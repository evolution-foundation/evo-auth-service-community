# frozen_string_literal: true

module DataPrivacyConsentSerializer
  extend self

  def full(consent)
    return nil unless consent

    {
      id: consent.id,
      user_id: consent.user_id,
      consent_type: consent.consent_type,
      consented: consent.consented,
      consented_at: consent.consented_at,
      ip_address: consent.ip_address,
      user_agent: consent.user_agent,
      created_at: consent.created_at,
      updated_at: consent.updated_at
    }
  end
end
