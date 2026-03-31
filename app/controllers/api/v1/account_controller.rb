# frozen_string_literal: true

class Api::V1::AccountController < Api::BaseController
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
end
