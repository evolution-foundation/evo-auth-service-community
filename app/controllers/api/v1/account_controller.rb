# frozen_string_literal: true

class Api::V1::AccountController < Api::BaseController
  PII_MASK_SETTING_KEY = 'mask_contact_pii'
  # Settings keys that only administrators may change. They can appear inside
  # either free-form blob permitted by account_params (`settings` or
  # `custom_attributes`), so without this explicit gate a non-admin could smuggle
  # a privileged value through an open hash. Any future security- or
  # billing-relevant key MUST be listed here to inherit the admin-only guard.
  ADMIN_ONLY_SETTINGS_KEYS = [PII_MASK_SETTING_KEY].freeze
  # Both free-form hashes account_params permits; a privileged key is guarded in
  # whichever blob it is sent through, not just `settings`.
  PRIVILEGED_SETTING_BLOBS = %w[settings custom_attributes].freeze
  ADMIN_ROLE_KEYS = %w[super_admin account_owner administrator admin].freeze

  before_action :check_authorization, only: :update
  before_action :enforce_admin_for_privileged_settings, only: :update

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

  # Only admins may change privileged settings (contact-PII mask and any other
  # key in ADMIN_ONLY_SETTINGS_KEYS). Check the EFFECTIVE change (current vs
  # incoming) instead of mere key presence — otherwise an agent could PATCH
  # `{ settings: { other_key: "x" } }` and rely on a shallow merge to wipe a
  # flag without ever naming it. The key is guarded in EITHER free-form blob
  # (`settings` or `custom_attributes`), so it cannot be smuggled through the
  # other hash.
  def enforce_admin_for_privileged_settings
    return if current_user_admin?

    privileged_change = PRIVILEGED_SETTING_BLOBS.any? do |blob|
      incoming = params.dig(:account, blob)
      next false unless incoming.is_a?(ActionController::Parameters) || incoming.is_a?(Hash)

      ADMIN_ONLY_SETTINGS_KEYS.any? do |key|
        # `key?` works on both ActionController::Parameters and Hash; avoid `to_h`
        # here because params are not yet permitted in a before_action and that
        # would raise UnfilteredParameters.
        next false unless incoming.key?(key)

        current_value = RuntimeConfig.account&.dig(blob, key)
        current_value != incoming[key]
      end
    end

    return unless privileged_change

    error_response('FORBIDDEN', 'Only admins can change privileged account settings', status: :forbidden)
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
