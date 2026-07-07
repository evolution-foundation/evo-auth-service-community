# frozen_string_literal: true

class Api::V1::AccountController < Api::BaseController
  PII_MASK_SETTING_KEY = 'mask_contact_pii'
  ADMIN_ROLE_KEYS = %w[super_admin account_owner administrator admin].freeze

  before_action :check_authorization, only: :update
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
    RuntimeConfig.set('account', deep_merge_account(account, updates))

    updated = RuntimeConfig.account
    success_response(data: updated.merge('role' => current_user&.role_data), message: 'Account updated successfully')
  end

  private

  def check_authorization
    authorize_resource!('accounts', 'update')
  end

  def account_params
    params.require(:account).permit(:name, :domain, :support_email, :locale,
                                    settings: {}, custom_attributes: {})
  end

  # Hash#merge is shallow — sending `settings: { foo: 1 }` would wipe every
  # other key under `settings`. Deep-merge nested hash keys so partial PATCHes
  # preserve sibling keys (e.g. mask_contact_pii stays put when only an
  # unrelated setting is updated).
  def deep_merge_account(account, updates)
    account.merge(updates) do |key, old_val, new_val|
      if %w[settings custom_attributes].include?(key.to_s) && old_val.is_a?(Hash) && new_val.is_a?(Hash)
        old_val.deep_merge(new_val)
      else
        new_val
      end
    end
  end

  # EVO-1551: only admins may flip the contact-PII mask. Check the EFFECTIVE
  # change (current vs incoming) instead of mere key presence — otherwise an
  # agent could PATCH `{ settings: { other_key: "x" } }` and rely on the (now
  # fixed) shallow merge to wipe the flag without ever naming it.
  def enforce_admin_for_mask_pii_change
    incoming_settings = params.dig(:account, :settings)
    return unless incoming_settings.is_a?(ActionController::Parameters) || incoming_settings.is_a?(Hash)
    # `key?` works on both ActionController::Parameters and Hash; avoid `to_h`
    # here because params are not yet permitted in a before_action and that
    # would raise UnfilteredParameters.
    return unless incoming_settings.key?(PII_MASK_SETTING_KEY)

    current_value = RuntimeConfig.account&.dig('settings', PII_MASK_SETTING_KEY)
    next_value = incoming_settings[PII_MASK_SETTING_KEY]
    return if current_value == next_value

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
