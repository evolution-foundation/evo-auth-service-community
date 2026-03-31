class Api::V1::DataPrivacyController < Api::BaseController
  before_action :check_authorization
  before_action :authenticate_user!
  before_action :set_privacy_service

  def dashboard
    dashboard_data = @privacy_service.privacy_dashboard_data

    success_response(data: {
      privacy_dashboard: dashboard_data,
      user_rights: user_rights_summary,
      quick_actions: quick_actions_available
    }, message: 'Privacy dashboard retrieved successfully')
  end

  def consents
    consent_status = @privacy_service.consent_status

    success_response(data: {
      consents: consent_status,
      available_types: DataPrivacyConsent::CONSENT_TYPES,
      legal_bases: DataPrivacyConsent::LEGAL_BASIS
    }, message: 'Consents retrieved successfully')
  end

  def grant_consent
    consent_type = params[:consent_type]
    legal_basis = params[:legal_basis] || 'consent'
    purpose = params[:purpose]
    expires_in = params[:expires_in]&.to_i&.days

    unless DataPrivacyConsent::CONSENT_TYPES.include?(consent_type)
      return error_response(
        'VALIDATION_ERROR',
        'Invalid consent type',
        details: { valid_types: DataPrivacyConsent::CONSENT_TYPES },
        status: :bad_request
      )
    end

    consent = @privacy_service.manage_consent(
      consent_type,
      'grant',
      legal_basis: legal_basis,
      purpose: purpose,
      expires_in: expires_in
    )

    success_response(
      data: { consent: DataPrivacyConsentSerializer.basic(consent) },
      message: 'Consent granted successfully'
    )
  end

  def revoke_consent
    consent_type = params[:consent_type]
    success = @privacy_service.manage_consent(consent_type, 'revoke')

    if success
      success_response(data: {}, message: 'Consent revoked successfully')
    else
      error_response('NOT_FOUND', 'Consent not found or already revoked', status: :not_found)
    end
  end

  def export_data
    format = params[:format] || 'json'

    unless %w[json csv xml].include?(format.downcase)
      return error_response(
        'VALIDATION_ERROR',
        'Invalid format',
        details: { supported_formats: %w[json csv xml] },
        status: :bad_request
      )
    end

    exported_data = @privacy_service.export_user_data(format: format)

    case format.downcase
    when 'json'
      success_response(data: JSON.parse(exported_data), message: 'User data exported successfully')
    when 'csv'
      send_data exported_data,
                filename: "user_data_#{current_user.id}_#{Date.current}.csv",
                type: 'text/csv'
    when 'xml'
      send_data exported_data,
                filename: "user_data_#{current_user.id}_#{Date.current}.xml",
                type: 'application/xml'
    end
  rescue => e
    error_response('OPERATION_FAILED', "Export failed: #{e.message}", status: :internal_server_error)
  end

  def data_portability
    portable_data = @privacy_service.generate_data_portability_package

    success_response(
      data: {
        package: portable_data,
        download_instructions: {
          description: 'This package contains your portable data in a standardized format',
          format_version: portable_data[:format_version],
          generated_at: portable_data[:generated_at]
        }
      },
      message: 'Data portability package generated'
    )
  rescue => e
    error_response('OPERATION_FAILED', "Portability package generation failed: #{e.message}", status: :internal_server_error)
  end

  def request_deletion
    reason = params[:reason]
    deletion_token = @privacy_service.request_data_deletion(reason: reason)

    success_response(
      data: {
        deletion_token: deletion_token,
        instructions: {
          description: 'Please confirm your deletion request using the provided token',
          confirmation_endpoint: '/api/v1/data_privacy/confirm_deletion',
          expires_in: '7 days',
          warning: 'This action cannot be undone. All your data will be permanently deleted.'
        }
      },
      message: 'Data deletion requested successfully'
    )
  rescue => e
    error_response('OPERATION_FAILED', "Deletion request failed: #{e.message}", status: :internal_server_error)
  end

  def confirm_deletion
    deletion_token = params[:deletion_token]
    confirmation = params[:confirmation]

    unless deletion_token.present?
      return error_response('BAD_REQUEST', 'Deletion token is required', status: :bad_request)
    end

    unless confirmation == 'DELETE_MY_DATA'
      return error_response(
        'VALIDATION_ERROR',
        'Confirmation phrase required',
        details: { required_phrase: 'DELETE_MY_DATA' },
        status: :bad_request
      )
    end

    @privacy_service.confirm_data_deletion(deletion_token)

    success_response(
      data: { status: 'completed', deleted_at: Time.current.iso8601 },
      message: 'Your data has been successfully deleted'
    )
  rescue ArgumentError => e
    error_response('BAD_REQUEST', e.message, status: :bad_request)
  rescue => e
    error_response('OPERATION_FAILED', "Deletion failed: #{e.message}", status: :internal_server_error)
  end

  private

  def set_privacy_service
    @privacy_service = DataPrivacyService.new(user: current_user, request: request)
  end

  def user_rights_summary
    [
      { right: 'Access', description: 'View and download your personal data', action: 'export_data', available: true },
      { right: 'Rectification', description: 'Correct inaccurate personal data', action: 'update_profile', available: true },
      { right: 'Erasure', description: 'Delete your personal data', action: 'request_deletion', available: true },
      { right: 'Portability', description: 'Transfer your data to another service', action: 'data_portability', available: true },
      { right: 'Restrict Processing', description: 'Limit how we process your data', action: 'manage_consents', available: true },
      { right: 'Object', description: 'Object to certain data processing', action: 'revoke_consent', available: true }
    ]
  end

  def quick_actions_available
    [
      { action: 'export_data', title: 'Download My Data', description: 'Get a copy of all your personal data', endpoint: 'GET /data_privacy/export' },
      { action: 'manage_consents', title: 'Manage Consents', description: 'Review and update your privacy preferences', endpoint: 'GET /data_privacy/consents' },
      { action: 'request_deletion', title: 'Delete My Account', description: 'Permanently delete your account and all data', endpoint: 'POST /data_privacy/deletion_request' }
    ]
  end

  def check_authorization
    action_map = {
      'dashboard' => 'data_privacy.view_dashboard',
      'consents' => 'data_privacy.manage_consents',
      'grant_consent' => 'data_privacy.manage_consents',
      'revoke_consent' => 'data_privacy.manage_consents',
      'export_data' => 'data_privacy.export_data',
      'data_portability' => 'data_privacy.export_data',
      'request_deletion' => 'data_privacy.delete_data',
      'confirm_deletion' => 'data_privacy.delete_data'
    }

    required_permission = action_map[action_name]
    if required_permission
      resource_key, action_key = required_permission.split('.')
      authorize_resource!(resource_key, action_key)
    else
      true
    end
  end
end
