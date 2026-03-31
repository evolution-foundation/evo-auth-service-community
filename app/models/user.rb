# == Schema Information
#
# Table name: users
#
#  id                     :uuid             not null, primary key
#  availability           :integer          default("online")
#  confirmation_sent_at   :datetime
#  confirmation_token     :string
#  confirmed_at           :datetime
#  consumed_timestep      :integer
#  current_sign_in_at     :datetime
#  current_sign_in_ip     :string
#  custom_attributes      :jsonb
#  display_name           :string
#  email                  :string
#  email_otp_attempts     :integer          default(0)
#  email_otp_secret       :string
#  email_otp_sent_at      :datetime
#  encrypted_password     :string           default(""), not null
#  failed_mfa_attempts    :integer          default(0)
#  last_mfa_failure_at    :datetime
#  last_sign_in_at        :datetime
#  last_sign_in_ip        :string
#  message_signature      :text
#  mfa_confirmed_at       :datetime
#  mfa_method             :integer          default("disabled"), not null
#  name                   :string           not null
#  otp_backup_codes       :text             default([]), is an Array
#  otp_required_for_login :boolean          default(FALSE), not null
#  otp_secret             :string
#  provider               :string           default("email"), not null
#  pubsub_token           :string
#  remember_created_at    :datetime
#  reset_password_sent_at :datetime
#  reset_password_token   :string
#  sign_in_count          :integer          default(0), not null
#  tokens                 :json
#  type                   :string
#  ui_settings            :jsonb
#  uid                    :string           default(""), not null
#  unconfirmed_email      :string
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#

class User < ApplicationRecord
  include AccessTokenable
  include AvailabilityStatusable
  include PermissionVerifiable
  include Pubsubable
  include DeviseTokenAuth::Concerns::User
  include Avatarable
  include SsoAuthenticatable
  include UserAttributeHelpers
  include TwoFactorAuthenticatable
  
  require "argon2"
  PASSWORD_SPECIAL_CHAR_REGEX = /[^A-Za-z0-9]/.freeze

  BASIC_READ_PERMISSIONS = %w[
    accounts.read labels.read dashboard.read inboxes.read teams.read users.read
  ].freeze

  devise :database_authenticatable,
         :registerable,
         :recoverable,
         :rememberable,
         :trackable,
         :validatable,
         :confirmable,
         :omniauthable, omniauth_providers: [:google_oauth2]

  enum availability: { online: 0, offline: 1, busy: 2 }

  validates :email, presence: true
  validate :password_complexity

  has_many :user_roles, dependent: :destroy
  has_many :roles, through: :user_roles

  before_validation :set_password_and_uid, on: :create

  scope :order_by_full_name, -> { order('lower(name) ASC') }

  before_validation do
    self.email = email.try(:downcase)
  end
  
  # Verifica se o usuário tem permissão para realizar uma ação específica em um recurso
  # @param resource [String] Recurso (ex: 'users', 'accounts')
  # @param action [String] Ação (ex: 'read', 'create', 'update', 'delete')
  def can?(resource, action)
    has_permission?("#{resource}.#{action}")
  end

  def has_permission?(permission_key)
    return false unless permission_key.present?
    return true if BASIC_READ_PERMISSIONS.include?(permission_key)

    user_roles.joins(role: :role_permissions_actions)
              .where(role_permissions_actions: { permission_key: permission_key })
              .exists?
  end
  
  # Verifica se o usuário tem uma role específica
  # @param role_key [String] Chave da role
  def has_role?(role_key)
    return false unless persisted?
    return false if role_key.blank?

    # Se as associações estão carregadas, usar cache
    if association(:user_roles).loaded?
      user_roles.any? { |ur| ur.role&.key == role_key }
    else
      # Caso contrário, fazer query
      user_roles.joins(:role).where(roles: { key: role_key }).exists?
    end
  end
  
  # Lista todas as permissões do usuário
  def permissions
    all_permissions
  end

  def all_permissions
    return BASIC_READ_PERMISSIONS.dup unless persisted?

    role_perms = user_roles.joins(role: :role_permissions_actions)
                           .pluck('role_permissions_actions.permission_key')
    (BASIC_READ_PERMISSIONS + role_perms).uniq.sort
  end
  
  # Lista permissões agrupadas por recurso
  def permissions_by_resource
    all_permissions.each_with_object({}) do |permission_key, hash|
      resource, action = permission_key.split('.', 2)
      next unless resource && action

      hash[resource] ||= []
      hash[resource] << action
    end
  end
  
  # Retorna a role do usuário (busca na user_roles - nível de usuário)
  def role_data
    return nil unless persisted?
    return @role_data if defined?(@role_data)
    
    # Use eager loaded association if available, otherwise query
    user_role = if association(:user_roles).loaded?
      # When eager loaded, use the loaded collection (no query)
      user_roles.first
    else
      # Fallback to query when not eager loaded
      user_roles.joins(:role).first
    end
    
    return @role_data = nil unless user_role
    
    # Access role - will use eager loaded association if available
    role = user_role.role
    @role_data = role ? {
      id: role.id,
      key: role.key,
      name: role.name
    } : nil
  end
  
  # Métodos de autenticação movidos para seção pública para uso em seeds
  def password=(new_password)
    @password = new_password
    if new_password.present?
      self.encrypted_password = Argon2::Password.create(new_password)
    end
  end

  def type
    read_attribute(:type) || 'User'
  end

  def password
    @password
  end

  def valid_password?(password_to_check)
    return false if encrypted_password.blank? || password_to_check.blank?
    
    begin
      Argon2::Password.verify_password(password_to_check, encrypted_password)
    rescue => e
      Rails.logger.error "Erro ao verificar senha: #{e.class} - #{e.message}"
      false
    end
  end

  def self.from_email(email)
    find_by(email: email&.downcase)
  end

  def auto_offline
    false
  end

  def send_devise_notification(notification, *)
    devise_mailer.send(notification, self, *).deliver_later
  end

  def serializable_hash(options = nil)
    super(options).merge(confirmed: confirmed?)
  end

  def push_event_data
    {
      id: id,
      name: name,
      available_name: available_name,
      avatar_url: avatar_url,
      type: 'user',
      availability_status: availability_status,
      thumbnail: avatar_url
    }
  end

  def webhook_data
    {
      id: id,
      name: name,
      email: email,
      type: 'user'
    }
  end

  # Email reconfirmation flow protection
  def will_save_change_to_email?
    mutations_from_database.changed?('email')
  end

  def available_name
    name.presence || email
  end

  private

  def set_password_and_uid
    self.uid = email
  end

  def generate_sso_link
    # Placeholder for SSO link generation
    # This would generate a secure link for single sign-on
    "#{ENV['FRONTEND_URL']}/sso?token=#{SecureRandom.hex(32)}&user_id=#{id}"
  end



  scope :order_by_full_name, -> { order('lower(name) ASC') }

  def password_complexity
    return if password.blank?

    unless password.match?(/[a-z]/)
      errors.add(:password, 'must include at least one lowercase letter')
    end

    unless password.match?(/[A-Z]/)
      errors.add(:password, 'must include at least one uppercase letter')
    end

    unless password.match?(/\d/)
      errors.add(:password, 'must include at least one number')
    end

    unless password.match?(PASSWORD_SPECIAL_CHAR_REGEX)
      errors.add(:password, 'must include at least one special character')
    end
  end
end
