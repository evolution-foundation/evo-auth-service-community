class DataPrivacyService
  include ActiveModel::Model
  
  attr_accessor :user, :request

  def initialize(user:, request: nil)
    @user = user
    @request = request
  end

  # GDPR Article 15 - Right of Access (Data Portability)
  def export_user_data(format: 'json')
    data = compile_user_data
    
    case format.downcase
    when 'json'
      export_json(data)
    when 'csv'
      export_csv(data)
    when 'xml'
      export_xml(data)
    else
      raise ArgumentError, "Unsupported format: #{format}"
    end
  end

  # GDPR Article 17 - Right to Erasure (Right to be Forgotten)
  def delete_user_data
    ActiveRecord::Base.transaction do
      # 1. Anonymize personal data
      anonymize_personal_data
      
      # 2. Delete associated records
      delete_associated_records
      
      # 3. Mark user as deleted
      mark_user_as_deleted
      
      # 4. Revoke all active sessions and tokens
      revoke_all_sessions
    end
  end

  # GDPR Article 20 - Right to Data Portability
  def generate_data_portability_package
    data = compile_portable_data
    
    # Create a comprehensive package
    package = {
      user_profile: data[:profile],
      authentication_data: data[:authentication],
      consent_history: data[:consents],
      account_data: data[:account],
      oauth_applications: data[:oauth_apps],
      access_tokens: data[:tokens],
      generated_at: Time.current.iso8601,
      format_version: '1.0'
    }
    
    package
  end

  # GDPR Article 7 - Consent Management
  def manage_consent(consent_type, action, legal_basis: 'consent', purpose: nil, expires_in: nil)
    case action.to_s
    when 'grant'
      DataPrivacyConsent.grant_consent(
        user,
        consent_type,
        legal_basis: legal_basis,
        purpose: purpose,
        expires_in: expires_in,
        ip_address: request&.remote_ip,
        user_agent: request&.user_agent
      )
    when 'revoke'
      DataPrivacyConsent.revoke_consent(
        user,
        consent_type,
        ip_address: request&.remote_ip,
        user_agent: request&.user_agent
      )
    else
      raise ArgumentError, "Invalid action: #{action}. Use 'grant' or 'revoke'"
    end
  end

  # Get user's current consent status
  def consent_status
    DataPrivacyConsent.consent_summary(user)
  end

  # GDPR Article 12 - Transparent Information
  def privacy_dashboard_data
    {
      user_profile: basic_profile_data,
      data_categories: data_categories_collected,
      consent_status: consent_status,
      data_retention_periods: data_retention_info,
      third_party_sharing: third_party_sharing_info,
      user_rights: user_rights_info,
      contact_info: data_protection_contact_info,
      last_updated: Time.current.iso8601
    }
  end

  # Request data deletion (with confirmation process)
  def request_data_deletion(reason: nil)
    # Create a deletion request that requires confirmation
    deletion_token = SecureRandom.urlsafe_base64(32)
    
    # Store deletion request temporarily
    Rails.cache.write(
      "deletion_request:#{user.id}:#{deletion_token}",
      {
        user_id: user.id,
        reason: reason,
        requested_at: Time.current,
        ip_address: request&.remote_ip
      },
      expires_in: 7.days
    )
    
    # Return confirmation token
    deletion_token
  end

  # Confirm data deletion
  def confirm_data_deletion(deletion_token)
    cache_key = "deletion_request:#{user.id}:#{deletion_token}"
    deletion_request = Rails.cache.read(cache_key)
    
    unless deletion_request
      raise ArgumentError, "Invalid or expired deletion token"
    end
    
    # Perform the deletion
    delete_user_data
    
    # Clean up the request
    Rails.cache.delete(cache_key)
    
    true
  end

  private

  def compile_user_data
    {
      profile: user_profile_data,
      authentication: authentication_data,
      account: account_data,
      oauth_applications: oauth_application_data,
      access_tokens: access_token_data,
      consents: consent_data,
      mfa_settings: mfa_data
    }
  end

  def compile_portable_data
    # Only include data that should be portable (exclude system-specific IDs, etc.)
    {
      profile: portable_profile_data,
      authentication: portable_authentication_data,
      consents: consent_data,
      account: portable_account_data,
      oauth_apps: portable_oauth_data,
      tokens: portable_token_data
    }
  end

  def user_profile_data
    user.as_json(only: [:name, :email, :display_name, :created_at, :updated_at, :confirmed_at])
  end

  def portable_profile_data
    user.as_json(
      only: [:name, :email, :display_name, :created_at, :confirmed_at]
    )
  end

  def authentication_data
    {
      sign_in_count: user.sign_in_count,
      current_sign_in_at: user.current_sign_in_at,
      last_sign_in_at: user.last_sign_in_at,
      confirmed_at: user.confirmed_at,
      provider: user.provider,
      mfa_enabled: user.two_factor_enabled?,
      mfa_method: user.mfa_method
    }
  end

  def portable_authentication_data
    {
      provider: user.provider,
      mfa_enabled: user.two_factor_enabled?,
      account_created: user.created_at
    }
  end

  def account_data
    account = RuntimeConfig.account
    account ? account.slice('name', 'status', 'locale') : {}
  end

  def portable_account_data
    account = RuntimeConfig.account
    account ? account.slice('name', 'locale') : {}
  end

  def oauth_application_data
    OauthApplication.all.as_json(only: [:name, :redirect_uri, :scopes, :created_at])
  end

  def portable_oauth_data
    OauthApplication.all.as_json(only: [:name, :scopes, :created_at])
  end

  def access_token_data
    # Only include metadata, not actual tokens
    # Note: access_tokens association may not exist in this User model
    if user.respond_to?(:access_tokens)
      user.access_tokens.as_json(
        only: [:created_at, :last_used_at, :expires_at]
      )
    else
      []
    end
  end

  def portable_token_data
    # Minimal token metadata for portability
    if user.respond_to?(:access_tokens)
      user.access_tokens.count
    else
      0
    end
  end

  def consent_data
    DataPrivacyConsent.where(user: user).as_json(
      only: [:consent_type, :granted, :granted_at, :revoked_at, :legal_basis, :purpose_description]
    )
  end

  def mfa_data
    {
      method: user.mfa_method,
      enabled: user.two_factor_enabled?,
      confirmed_at: user.mfa_confirmed_at,
      backup_codes_count: user.otp_backup_codes&.length || 0
    }
  end

  def anonymize_personal_data
    user.update!(
      name: "Deleted User #{user.id}",
      email: "deleted-#{user.id}@deleted.local",
      display_name: nil,
      encrypted_password: '',
      reset_password_token: nil,
      confirmation_token: nil,
      unconfirmed_email: nil,
      otp_secret: nil,
      otp_backup_codes: [],
      email_otp_secret: nil,
      custom_attributes: {},
      ui_settings: {},
      message_signature: nil
    )
  end

  def delete_associated_records
    # Delete user's access tokens
    user.access_tokens.destroy_all if user.respond_to?(:access_tokens)

    # Delete consents
    DataPrivacyConsent.where(user: user).destroy_all
  end

  def mark_user_as_deleted
    user.update!(
      type: 'DeletedUser',
      confirmed_at: nil,
      provider: 'deleted'
    )
  end

  def revoke_all_sessions
    # Revoke all Devise sessions
    user.tokens = {}
    user.save!
    
    # Revoke OAuth tokens (if association exists)
    if user.respond_to?(:access_tokens)
      user.access_tokens.pluck(:token).each { |t| TokenValidationService.invalidate_cache_for_token(t) }
      user.access_tokens.update_all(revoked_at: Time.current)
    end
  end

  def export_json(data)
    {
      data: data,
      exported_at: Time.current.iso8601,
      format: 'json',
      version: '1.0'
    }.to_json
  end

  def export_csv(data)
    require 'csv'
    
    CSV.generate(headers: true) do |csv|
      # Flatten the nested data structure for CSV
      flattened_data = flatten_hash(data)
      
      csv << flattened_data.keys
      csv << flattened_data.values
    end
  end

  def export_xml(data)
    require 'builder'
    
    xml = Builder::XmlMarkup.new(indent: 2)
    xml.instruct!
    xml.user_data do
      xml.exported_at Time.current.iso8601
      xml.format 'xml'
      xml.version '1.0'
      
      build_xml_from_hash(xml, data)
    end
  end

  def flatten_hash(hash, parent_key = '', sep = '.')
    hash.each_with_object({}) do |(k, v), h|
      new_key = parent_key.empty? ? k : "#{parent_key}#{sep}#{k}"
      if v.is_a?(Hash)
        h.merge!(flatten_hash(v, new_key, sep))
      else
        h[new_key] = v
      end
    end
  end

  def build_xml_from_hash(xml, hash)
    hash.each do |key, value|
      if value.is_a?(Hash)
        xml.tag!(key) do
          build_xml_from_hash(xml, value)
        end
      elsif value.is_a?(Array)
        xml.tag!(key) do
          value.each_with_index do |item, index|
            xml.tag!("item_#{index}", item)
          end
        end
      else
        xml.tag!(key, value)
      end
    end
  end

  def basic_profile_data
    {
      name: user.name,
      email: user.email,
      created_at: user.created_at,
      last_sign_in: user.last_sign_in_at
    }
  end

  def data_categories_collected
    [
      {
        category: 'Identity Data',
        description: 'Name, email address, user ID',
        retention_period: 'Until account deletion',
        legal_basis: 'Contract performance'
      },
      {
        category: 'Authentication Data',
        description: 'Login credentials, MFA settings, session data',
        retention_period: 'Until account deletion',
        legal_basis: 'Contract performance'
      },
      {
        category: 'Usage Data',
        description: 'Login history, API usage',
        retention_period: '2 years after last activity',
        legal_basis: 'Legitimate interests'
      },
      {
        category: 'Technical Data',
        description: 'IP address, user agent, device information',
        retention_period: '1 year',
        legal_basis: 'Legitimate interests'
      }
    ]
  end

  def data_retention_info
    {
      profile_data: '7 years after account deletion (legal requirement)',
      authentication_logs: '2 years after last login',
      session_data: '30 days after session end',
      oauth_tokens: 'Until revoked or expired'
    }
  end

  def third_party_sharing_info
    [
      {
        party: 'OAuth Applications',
        purpose: 'Single Sign-On authentication',
        data_shared: 'Profile information as consented',
        legal_basis: 'Consent'
      }
    ]
  end

  def user_rights_info
    [
      'Right to access your personal data',
      'Right to rectify inaccurate data',
      'Right to erase your data',
      'Right to restrict processing',
      'Right to data portability',
      'Right to object to processing',
      'Right to withdraw consent'
    ]
  end

  def data_protection_contact_info
    {
      email: ENV['DPO_EMAIL'] || 'privacy@example.com',
      address: ENV['DPO_ADDRESS'] || 'Data Protection Officer, Company Address',
      phone: ENV['DPO_PHONE'] || '+1-555-0123'
    }
  end

end
