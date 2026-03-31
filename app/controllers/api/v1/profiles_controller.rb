class Api::V1::ProfilesController < Api::BaseController
  include AccountSerializerHelper
  
  before_action :check_authorization
  
  def show
    account = account_data
    accounts = account.present? ? [account.merge('role' => current_user.role_data)] : []

    success_response(
      data: {
        user: profile_data(current_user),
        accounts: accounts
      },
      message: 'Profile retrieved successfully'
    )
  end

  def update
    avatar_param = params.dig(:profile, :avatar) || params[:avatar]
    if avatar_param.present?
      current_user.avatar.attach(avatar_param)
    end

    filtered_params = profile_params

    if current_user.update(filtered_params)
      message = if current_user.unconfirmed_email.present?
                  'Profile updated. Confirmation email sent to the new address.'
                else
                  'Profile updated successfully'
                end
      success_response(
        data: profile_data(current_user),
        message: message
      )
    else
      render_unprocessable_entity(current_user.errors)
    end
  end

  def update_avatar
    if params[:avatar].present?
      current_user.avatar.attach(params[:avatar])
      if current_user.save
        success_response(
          data: { avatar_url: avatar_url(current_user) },
          message: 'Avatar updated successfully'
        )
      else
        render_unprocessable_entity(current_user.errors)
      end
    else
      error_response('VALIDATION_ERROR', 'No avatar file provided', status: :unprocessable_entity)
    end
  end

  def update_password
    unless params[:current_password].present? && params[:new_password].present?
      error_response('VALIDATION_ERROR', 'Current password and new password are required', status: :unprocessable_entity)
      return
    end

    if current_user.valid_password?(params[:current_password])
      if current_user.update(password: params[:new_password])
        success_response(data: {}, message: 'Password updated successfully')
      else
        render_unprocessable_entity(current_user.errors)
      end
    else
      error_response('UNAUTHORIZED', 'Current password is incorrect', status: :unprocessable_entity)
    end
  end

  def cancel_email_change
    unless current_user.unconfirmed_email.present?
      return error_response('VALIDATION_ERROR', 'No pending email change', status: :unprocessable_entity)
    end
    if current_user.update(unconfirmed_email: nil)
      success_response(data: profile_data(current_user), message: 'Email change cancelled')
    else
      render_unprocessable_entity(current_user.errors)
    end
  end

  def resend_email_confirmation
    unless current_user.pending_reconfirmation?
      return error_response('VALIDATION_ERROR', 'No pending email confirmation', status: :unprocessable_entity)
    end
    current_user.send_confirmation_instructions
    success_response(data: {}, message: 'Confirmation email resent')
  end

  def notifications
    # Get notification preferences - for now return default structure
    success_response(
      data: {
        email_notifications: true,
        push_notifications: true,
        marketing_emails: false,
        security_alerts: true
      },
      message: 'Notification preferences retrieved successfully'
    )
  end

  def update_notifications
    # Update notification preferences - for now just return success
    success_response(
      data: {
        notifications: {
          email_notifications: params[:email_notifications] || true,
          push_notifications: params[:push_notifications] || true,
          marketing_emails: params[:marketing_emails] || false,
          security_alerts: params[:security_alerts] || true
        }
      },
      message: 'Notification preferences updated successfully'
    )
  end

  private

  def profile_params
    # Accept both direct params and profile[...] format for compatibility
    if params[:profile].present?
      params.require(:profile).permit(:name, :email, :display_name, :message_signature,
                    custom_attributes: {}, ui_settings: {})
    else
      params.permit(:name, :email, :display_name, :message_signature,
                    custom_attributes: {}, ui_settings: {})
    end
  end

  def profile_data(user)
    {
      id: user.id,
      name: user.name,
      email: user.email,
      display_name: user.display_name,
      message_signature: user.message_signature,
      availability: user.availability,
      mfa_enabled: user.mfa_enabled?,
      confirmed: user.confirmed?,
      unconfirmed_email: user.unconfirmed_email,
      avatar_url: avatar_url(user),
      custom_attributes: user.custom_attributes || {},
      ui_settings: user.ui_settings || {},
      created_at: user.created_at,
      updated_at: user.updated_at
    }
  end

  def avatar_url(user)
    user.avatar_url.presence
  end

  def check_authorization
    # Verificar se usuário tem permissão para gerenciar seu próprio perfil
    action_map = {
      'show' => 'profiles.read',
      'update' => 'profiles.update',
      'update_avatar' => 'profiles.update_avatar',
      'update_password' => 'profiles.update_password',
      'cancel_email_change' => 'profiles.update',
      'resend_email_confirmation' => 'profiles.update',
      'notifications' => 'profiles.read',
      'update_notifications' => 'profiles.manage_notifications'
    }
    
    required_permission = action_map[action_name]
    if required_permission
      resource_key, action_key = required_permission.split('.')
      authorize_resource!(resource_key, action_key)
    else
      true # Para ações não mapeadas, permitir por enquanto
    end
  end
end
