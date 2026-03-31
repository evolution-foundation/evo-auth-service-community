class Api::V1::MfaController < Api::BaseController
  skip_before_action :authenticate_request!, only: [:verify_totp, :verify_email_otp]
  before_action :authenticate_verification_request!, only: [:verify_totp, :verify_email_otp]

  def setup_totp
    current_user.generate_otp_secret!
    current_user.generate_otp_backup_codes!

    success_response(
      data: {
        secret: current_user.otp_secret,
        qr_code_url: current_user.generate_qr_code,
        backup_codes: current_user.otp_backup_codes
      },
      message: 'TOTP setup completed successfully'
    )
  end

  def verify_totp
    user = current_user || find_mfa_user
    unless user
      return error_response('RESOURCE_NOT_FOUND', 'User not found', status: :not_found)
    end

    return render_invalid_code if params[:code].blank?

    if user.verify_totp(params[:code])
      complete_mfa_setup(user, :totp) if setup_request?
      render_successful_verification(user, issue_token: !setup_request?)
    else
      render_invalid_code
    end
  end

  def setup_email_otp
    code = current_user.generate_email_otp
    UserMailer.two_factor_authentication_code(current_user, code).deliver_later

    success_response(data: {}, message: 'Email OTP sent successfully')
  end

  def verify_email_otp
    user = current_user || find_mfa_user
    unless user
      return error_response('RESOURCE_NOT_FOUND', 'User not found', status: :not_found)
    end

    return render_invalid_code if params[:code].blank?

    if user.validate_email_otp(params[:code])
      complete_mfa_setup(user, :email) if setup_request?
      render_successful_verification(user, issue_token: !setup_request?)
    else
      render_invalid_code
    end
  end

  def backup_codes
    success_response(
      data: { backup_codes: current_user.otp_backup_codes },
      message: 'Backup codes retrieved successfully'
    )
  end

  def regenerate_backup_codes
    current_user.generate_backup_codes
    current_user.save!

    success_response(
      data: { backup_codes: current_user.otp_backup_codes },
      message: 'Backup codes regenerated successfully'
    )
  end

  def disable
    current_user.disable_two_factor!

    success_response(data: {}, message: 'MFA disabled successfully')
  end

  private

  def authenticate_verification_request!
    return if session[:mfa_user_id].present?

    authenticate_request!
  end

  def find_mfa_user
    return unless session[:mfa_user_id]

    User.find_by(id: session[:mfa_user_id])
  end

  def complete_mfa_setup(user, method)
    user.update!(
      mfa_method: method,
      otp_required_for_login: true,
      mfa_confirmed_at: Time.current
    )
  end

  def render_successful_verification(user, issue_token:)
    session.delete(:mfa_user_id)
    access_token = issue_token ? user.create_access_token : nil

    data = {
      user: user_data(user),
      accounts: [RuntimeConfig.account].compact
    }
    if access_token
      data[:access_token] = access_token.token
      data[:token_type] = 'Bearer'
    end

    success_response(data: data, message: 'MFA verification successful')
  end

  def render_invalid_code
    error_response('VALIDATION_ERROR', 'Invalid verification code', status: :unprocessable_entity)
  end

  def setup_request?
    ActiveModel::Type::Boolean.new.cast(params[:setup])
  end

  def user_data(user)
    {
      id: user.id,
      name: user.name,
      email: user.email,
      display_name: user.display_name,
      availability: user.availability,
      mfa_enabled: user.mfa_enabled?,
      confirmed: user.confirmed?
    }
  end
end
