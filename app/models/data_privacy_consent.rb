# == Schema Information
#
# Table name: data_privacy_consents
#
#  id                  :bigint           not null, primary key
#  user_id             :bigint           not null
#  consent_type        :string           not null
#  granted             :boolean          default(FALSE), not null
#  granted_at          :datetime
#  revoked_at          :datetime
#  ip_address          :string
#  user_agent          :text
#  details             :jsonb            default({})
#  legal_basis         :string
#  purpose_description :text
#  expires_at          :datetime
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#

class DataPrivacyConsent < ApplicationRecord
  belongs_to :user

  # Consent types based on GDPR/LGPD requirements
  CONSENT_TYPES = %w[
    data_processing
    marketing_communications
    analytics_tracking
    third_party_sharing
    profiling
    automated_decision_making
    data_retention
    cross_border_transfer
    sensitive_data_processing
    cookies_functional
    cookies_analytics
    cookies_marketing
  ].freeze

  # GDPR Legal Basis
  LEGAL_BASIS = %w[
    consent
    contract
    legal_obligation
    vital_interests
    public_task
    legitimate_interests
  ].freeze

  validates :consent_type, presence: true, inclusion: { in: CONSENT_TYPES }
  validates :legal_basis, inclusion: { in: LEGAL_BASIS }, allow_blank: true
  validates :user_id, uniqueness: { scope: :consent_type }, on: :create

  scope :granted, -> { where(granted: true, revoked_at: nil) }
  scope :revoked, -> { where.not(revoked_at: nil) }
  scope :active, -> { granted.where('expires_at IS NULL OR expires_at > ?', Time.current) }
  scope :expired, -> { where('expires_at IS NOT NULL AND expires_at <= ?', Time.current) }
  scope :by_type, ->(type) { where(consent_type: type) }

  # Grant consent
  def grant!(ip_address: nil, user_agent: nil, details: {})
    update!(
      granted: true,
      granted_at: Time.current,
      revoked_at: nil,
      ip_address: ip_address,
      user_agent: user_agent,
      details: details
    )
  end

  # Revoke consent
  def revoke!(ip_address: nil, user_agent: nil, details: {})
    update!(
      granted: false,
      revoked_at: Time.current,
      ip_address: ip_address,
      user_agent: user_agent,
      details: details.merge(revocation_details: details)
    )
  end

  # Check if consent is currently valid
  def valid_consent?
    granted? && !revoked? && !expired?
  end

  def revoked?
    revoked_at.present?
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  # Class methods for consent management
  def self.grant_consent(user, consent_type, legal_basis: 'consent', purpose: nil, expires_in: nil, **options)
    consent = find_by(user: user, consent_type: consent_type)
    
    if consent
      # Update existing consent
      consent.legal_basis = legal_basis
      consent.purpose_description = purpose
      consent.expires_at = expires_in ? Time.current + expires_in : nil
      consent.grant!(**options)
    else
      # Create new consent
      consent = create!(
        user: user,
        consent_type: consent_type,
        legal_basis: legal_basis,
        purpose_description: purpose,
        expires_at: expires_in ? Time.current + expires_in : nil,
        granted: false
      )
      consent.grant!(**options)
    end
    
    consent
  end

  def self.revoke_consent(user, consent_type, **options)
    consent = find_by(user: user, consent_type: consent_type)
    return false unless consent

    consent.revoke!(**options)
    true
  end

  def self.has_valid_consent?(user, consent_type)
    active.exists?(user: user, consent_type: consent_type)
  end

  def self.consent_summary(user)
    consents = where(user: user).includes(:user)
    
    CONSENT_TYPES.map do |type|
      consent = consents.find { |c| c.consent_type == type }
      
      {
        consent_type: type,
        granted: consent&.granted? || false,
        granted_at: consent&.granted_at,
        revoked_at: consent&.revoked_at,
        expires_at: consent&.expires_at,
        valid: consent&.valid_consent? || false,
        legal_basis: consent&.legal_basis,
        purpose: consent&.purpose_description
      }
    end
  end

  # Bulk operations for GDPR compliance
  def self.grant_essential_consents(user, **options)
    essential_types = %w[data_processing cookies_functional]
    
    essential_types.map do |type|
      grant_consent(
        user, 
        type, 
        legal_basis: 'contract',
        purpose: "Essential for service functionality",
        **options
      )
    end
  end

  def self.revoke_all_consents(user, **options)
    where(user: user, granted: true, revoked_at: nil).find_each do |consent|
      consent.revoke!(**options)
    end
  end
end
