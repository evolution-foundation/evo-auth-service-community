module TwoFactorAuthenticatable
  extend ActiveSupport::Concern

  included do
    # MFA methods enum - avoiding 'none' as it conflicts with ActiveRecord
    enum mfa_method: {
      disabled: 0,
      totp: 1,
      email: 2
    }

    # Note: OTP secret will be stored encrypted in production
    # For now storing directly - can be enhanced with attr_encrypted gem later

    # Callbacks
    before_save :clear_mfa_fields_if_disabled
  end

  # TOTP (Authenticator App) Methods
  def generate_otp_secret!
    secret = ROTP::Base32.random
    # Use direct SQL update to bypass model callbacks
    User.where(id: id).update_all(otp_secret: secret)
    self.otp_secret = secret # Update the instance
    true
  end

  def otp_provisioning_uri(label = email, issuer: ENV.fetch('MFA_ISSUER', 'Evo Auth Service'))
    return unless otp_secret.present?

    totp = ROTP::TOTP.new(otp_secret, issuer: issuer)
    totp.provisioning_uri(label)
  end

  def generate_qr_code
    return unless otp_secret.present?

    provisioning_uri = otp_provisioning_uri
    return unless provisioning_uri

    qrcode = RQRCode::QRCode.new(provisioning_uri)
    qrcode.as_svg(
      offset: 0,
      color: '000',
      shape_rendering: 'crispEdges',
      module_size: 4,
      standalone: true
    )
  end

  def validate_otp(code)
    return false unless otp_secret.present?

    totp = ROTP::TOTP.new(otp_secret)
    timestamp = totp.verify(code, drift_behind: 30, drift_ahead: 30)
    
    if timestamp
      # Prevent replay attacks
      if consumed_timestep && timestamp <= consumed_timestep
        return false
      end
      
      update(consumed_timestep: timestamp)
      true
    else
      # Check backup codes
      check_backup_code(code)
    end
  end

  # Backup Codes Methods
  def generate_otp_backup_codes!
    codes = Array.new(10) { SecureRandom.alphanumeric(8).upcase }
    # Use direct SQL update to bypass model callbacks
    User.where(id: id).update_all(otp_backup_codes: codes)
    self.otp_backup_codes = codes # Update the instance
    codes
  end

  def check_backup_code(code)
    return false unless otp_backup_codes.present?

    code = code.upcase.strip
    if otp_backup_codes.include?(code)
      # Remove used backup code
      otp_backup_codes.delete(code)
      save!
      true
    else
      false
    end
  end

  # Email OTP Methods
  def generate_email_otp
    # Generate 6-digit code
    code = SecureRandom.random_number(1_000_000).to_s.rjust(6, '0')
    
    update!(
      email_otp_secret: code,
      email_otp_sent_at: Time.current,
      email_otp_attempts: 0
    )
    
    code
  end

  def validate_email_otp(code)
    return false unless email_otp_secret.present?
    return false if email_otp_expired?

    # Check attempts
    if email_otp_attempts >= 5
      clear_email_otp!
      return false
    end

    if email_otp_secret == code.to_s.strip
      clear_email_otp!
      true
    else
      increment!(:email_otp_attempts)
      false
    end
  end

  def email_otp_expired?
    return true unless email_otp_sent_at

    # OTP expires after 10 minutes
    email_otp_sent_at < 10.minutes.ago
  end

  def clear_email_otp!
    update!(
      email_otp_secret: nil,
      email_otp_sent_at: nil,
      email_otp_attempts: 0
    )
  end

  # MFA Management Methods
  def enable_two_factor!(method = :totp)
    # First enable MFA to prevent the callback from clearing fields
    update!(
      mfa_method: method,
      otp_required_for_login: true
    )
    
    case method.to_sym
    when :totp
      generate_otp_secret! unless otp_secret.present?
      generate_otp_backup_codes! if otp_backup_codes.blank?
    when :email
      # No special setup needed for email
    else
      raise ArgumentError, "Invalid MFA method: #{method}"
    end
  end

  def disable_two_factor!
    update!(
      otp_secret: nil,
      otp_required_for_login: false,
      otp_backup_codes: [],
      mfa_method: :disabled,
      consumed_timestep: nil,
      email_otp_secret: nil,
      email_otp_sent_at: nil,
      email_otp_attempts: 0,
      mfa_confirmed_at: nil
    )
  end

  def two_factor_enabled?
    otp_required_for_login?
  end

  def two_factor_setup_complete?
    two_factor_enabled? && mfa_confirmed_at.present?
  end

  def confirm_two_factor!
    update!(mfa_confirmed_at: Time.current)
  end

  # MFA Verification Tracking
  def record_failed_mfa_attempt!
    update!(
      failed_mfa_attempts: failed_mfa_attempts + 1,
      last_mfa_failure_at: Time.current
    )
  end

  def reset_failed_mfa_attempts!
    update!(
      failed_mfa_attempts: 0,
      last_mfa_failure_at: nil
    )
  end

  def mfa_locked?
    failed_mfa_attempts >= 5 && last_mfa_failure_at && last_mfa_failure_at > 15.minutes.ago
  end

  # Compatibility methods for auth service
  def mfa_enabled?
    two_factor_enabled? && mfa_confirmed_at.present?
  end

  def totp_enabled?
    totp? && otp_secret.present?
  end

  def email_otp_enabled?
    email? && email_otp_secret.present?
  end

  # Alias methods for backward compatibility
  alias_method :verify_totp, :validate_otp
  alias_method :verify_backup_code, :check_backup_code

  private

  def clear_mfa_fields_if_disabled
    return if otp_required_for_login?
    return if consumed_timestep_changed? && otp_secret.present?
    return if email_otp_secret_changed? && email_otp_secret.present?

    self.otp_secret = nil
    self.otp_backup_codes = []
    self.consumed_timestep = nil
    self.email_otp_secret = nil
    self.email_otp_sent_at = nil
    self.email_otp_attempts = 0
    self.mfa_confirmed_at = nil
  end
end