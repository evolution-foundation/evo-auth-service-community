# frozen_string_literal: true

class Api::V1::AccountController < Api::BaseController
  PII_MASK_SETTING_KEY = 'mask_contact_pii'
  ADMIN_ROLE_KEYS = %w[super_admin account_owner administrator admin].freeze

  before_action :enforce_admin_for_mask_pii_change, only: :update

  def show
    account = RuntimeConfig.account
    return error_response('NOT_FOUND', 'Account not configured', status: :not_found) unless account

    success_response(data: account.merge('role' => current_user&.role_data), message: 'Account retrieved successfully')
  end

  def update
    account = RuntimeConfig.account
    return error_response('NOT_FOUND', 'Account not configured', status: :not_found) unless account

    allowed = %w[name domain support_email locale settings custom_attributes]
    updates = account_params.to_h.slice(*allowed)
    RuntimeConfig.set('account', account.merge(updates))

    updated = RuntimeConfig.account
    success_response(data: updated.merge('role' => current_user&.role_data), message: 'Account updated successfully')
  end

  private

  def account_params
    params.require(:account).permit(:name, :domain, :support_email, :locale,
                                    settings: {}, custom_attributes: {})
  end

  # EVO-1551: only admins may flip the contact-PII mask. Without this, an agent
  # could PATCH /account directly via curl and disable masking even though the
  # UI toggle is hidden for them.
  def enforce_admin_for_mask_pii_change
    incoming_settings = params.dig(:account, :settings)
    return unless incoming_settings.is_a?(ActionController::Parameters) || incoming_settings.is_a?(Hash)
    return unless incoming_settings.to_h.key?(PII_MASK_SETTING_KEY)

    return if current_user_admin?

    error_response('FORBIDDEN', 'Only admins can change contact data masking', status: :forbidden)
  end

  def current_user_admin?
    return false unless current_user

    keys = if current_user.respond_to?(:roles)
             current_user.roles.pluck(:key)
           else
             []
           end
    (keys & ADMIN_ROLE_KEYS).any?
  end
end
