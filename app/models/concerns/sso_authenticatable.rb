module SsoAuthenticatable
  extend ActiveSupport::Concern

  def generate_sso_auth_token
    token = SecureRandom.hex(32)
    Rails.cache.write(sso_token_key(token), true, expires_in: 5.minutes)
    token
  end

  def invalidate_sso_auth_token(token)
    Rails.cache.delete(sso_token_key(token))
  end

  def valid_sso_auth_token?(token)
    Rails.cache.read(sso_token_key(token)).present?
  end

  def generate_sso_link
    encoded_email = ERB::Util.url_encode(email)
    "#{ENV.fetch('FRONTEND_URL', 'http://localhost:5173')}/app/login?email=#{encoded_email}&sso_auth_token=#{generate_sso_auth_token}"
  end

  def generate_sso_link_with_impersonation
    "#{generate_sso_link}&impersonation=true"
  end

  private

  def sso_token_key(token)
    "user_sso_auth_token:#{id}:#{token}"
  end
end
