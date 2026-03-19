class JwtService
  JWT_SECRET = Rails.application.credentials.secret_key_base || ENV.fetch('SECRET_KEY_BASE')
  JWT_ALGORITHM = 'HS256'

  class << self
    def encode(payload, expiration = 24.hours.from_now)
      payload[:exp] = expiration.to_i
      JWT.encode(payload, JWT_SECRET, JWT_ALGORITHM)
    end

    def decode(token)
      decoded = JWT.decode(token, JWT_SECRET, true, { algorithm: JWT_ALGORITHM })
      decoded[0]
    rescue JWT::DecodeError => e
      Rails.logger.error "JWT Decode Error: #{e.message}"
      nil
    end

    def generate_mfa_token(user_id, mfa_type)
      payload = {
        user_id: user_id,
        mfa_type: mfa_type,
        purpose: 'mfa_verification',
        iat: Time.current.to_i
      }
      
      # MFA tokens expire in 10 minutes
      encode(payload, 10.minutes.from_now)
    end

    def verify_mfa_token(token)
      payload = decode(token)
      return nil unless payload
      return nil unless payload['purpose'] == 'mfa_verification'
      
      payload
    end

    def generate_password_reset_token(user_id)
      payload = {
        user_id: user_id,
        purpose: 'password_reset',
        iat: Time.current.to_i
      }
      
      # Password reset tokens expire in 1 hour
      encode(payload, 1.hour.from_now)
    end

    def verify_password_reset_token(token)
      payload = decode(token)
      return nil unless payload
      return nil unless payload['purpose'] == 'password_reset'
      
      payload
    end
  end
end
