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

  # dashboard.read has no catalog resource ON PURPOSE (product decision, D2 of
  # the RBAC audit): the dashboard is the landing page of every authenticated
  # user, so the key lives only here and the frontend gate that reads it
  # always passes. Do not "clean it up" — removing it hides the home screen
  # from everyone.
  BASIC_READ_PERMISSIONS = %w[
    accounts.read labels.read dashboard.read teams.read
  ].freeze

  # Operational implications: holding a granular permission implies a minimal
  # operational read on dependent resources. A role with conversations.read
  # needs to load attendants (users.read) and inbox metadata (inboxes.read) to
  # operate the Conversations screen, even though those reads are no longer
  # granted to everyone via BASIC_READ_PERMISSIONS. The implied users.read is
  # OPERATIONAL only — the administrative gate (Settings > Agents) moved to
  # users.manage, so this does not re-open the admin panel.
  #
  # These also LOCK the implied key in the role editor: the user holds it
  # whatever the role says, so a checkbox for it would lie (see
  # ResourceActionsConfig.permission_lock_info). Only implications with that
  # property belong here — see GENERATED_WRITE_IMPLICATIONS.
  LOCKING_IMPLICATIONS = {
    'conversations.read' => %w[users.read inboxes.read]
  }.freeze

  # EVO-2127: holding any granular write of a resource implies its coarse
  # `<resource>.write`. The role editor now saves the coarse write groups; this
  # lets a non-super_admin who can already grant the granular writes also grant
  # the coarse write, so bulk_update_permissions does not 403 (it requires the
  # caller to hold every newly-granted key). Runtime-only (no save/backfill) and
  # forward-only: write is a leaf, create never implies delete. Derived from the
  # catalog so front (permissionDomains) and back cannot drift on which actions
  # are writes. Referencing ResourceActionsConfig here forces its autoload; there
  # is no cycle — the config reads User constants only at call time.
  #
  # Deliberately NOT in LOCKING_IMPLICATIONS: `<resource>.write` is a REAL,
  # editable grant — the coarse key is what the Write checkbox decides, and it is
  # the key that outlives the granular ones when enforcement migrates to it.
  # Locking it would make the editor able to add it but never remove it: the
  # front drops locked keys from the group the checkbox controls, so unchecking
  # "Write" would leave `<resource>.write` behind in the role forever.
  GENERATED_WRITE_IMPLICATIONS = ResourceActionsConfig.write_actions_by_resource
    .each_with_object({}) do |(resource, actions), acc|
      actions.each { |action| acc["#{resource}.#{action}"] = ["#{resource}.write"] }
    end.freeze

  # Every "can write this agent" key implies ai_agent_processor.execute — a system
  # key, runtime-only, never persisted. Granular writes are listed explicitly:
  # implications don't chain (has_permission? expands only a role's explicit keys).
  AGENT_EXECUTION_IMPLICATIONS = (
    ResourceActionsConfig.write_actions_by_resource.fetch('ai_agents', []) + ['write']
  ).each_with_object({}) do |action, acc|
    acc["ai_agents.#{action}"] = ['ai_agent_processor.execute']
  end.freeze

  # Runtime implications (has_permission? / all_permissions). Superset of
  # LOCKING_IMPLICATIONS. Block-form merge concatenates on key collision; a plain
  # .merge would drop the coarse write from GENERATED_WRITE_IMPLICATIONS and
  # silently undo EVO-2127.
  OPERATIONAL_IMPLICATIONS = LOCKING_IMPLICATIONS
                             .merge(GENERATED_WRITE_IMPLICATIONS)
                             .merge(AGENT_EXECUTION_IMPLICATIONS) { |_key, existing, added| (existing + added).uniq }
                             .freeze

  devise :database_authenticatable,
         :registerable,
         :recoverable,
         :rememberable,
         :trackable,
         :validatable,
         :confirmable,
         :omniauthable, omniauth_providers: [:google_oauth2, :github]

  enum availability: { online: 0, offline: 1, busy: 2 }

  validates :email, presence: true
  validate :password_complexity

  has_many :user_roles, dependent: :destroy
  has_many :roles, through: :user_roles
  has_many :user_tours, dependent: :destroy
  has_one :setup_survey_response, dependent: :destroy

  def setup_survey_completed?
    setup_survey_response.present?
  end

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

    explicit = role_permission_keys
    return true if explicit.include?(permission_key)

    # Operational implication: a role with conversations.read implies
    # users.read / inboxes.read (needed to operate the Conversations screen).
    OPERATIONAL_IMPLICATIONS.any? do |source_key, implied_keys|
      implied_keys.include?(permission_key) && explicit.include?(source_key)
    end
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

    role_perms = role_permission_keys
    combined = (BASIC_READ_PERMISSIONS + role_perms)

    # Inject operational implications so the frontend (PermissionsContext reads
    # all_permissions) agrees with has_permission? (API enforcement): a role
    # with conversations.read also has the implied users.read / inboxes.read.
    OPERATIONAL_IMPLICATIONS.each do |source_key, implied_keys|
      combined += implied_keys if combined.include?(source_key)
    end

    combined.uniq.sort
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

  # Permission keys granted explicitly via the user's roles (no BASIC, no
  # operational implications). Single source of truth for has_permission? and
  # all_permissions — keeps the implication logic from recursing into
  # has_permission?.
  def role_permission_keys
    return [] unless persisted?

    # Memoized per instance (User is per-request): has_permission? is called on
    # every authorize_resource!, and roles like account_owner/super_admin carry
    # hundreds of keys — without this we'd re-pluck the full set on each check.
    @role_permission_keys ||= user_roles.joins(role: :role_permissions_actions)
                                        .pluck('role_permissions_actions.permission_key')
  end

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

    errors.add(:password, :missing_lowercase, message: 'must include at least one lowercase letter') unless password.match?(/[a-z]/)
    errors.add(:password, :missing_uppercase, message: 'must include at least one uppercase letter') unless password.match?(/[A-Z]/)
    errors.add(:password, :missing_number, message: 'must include at least one number') unless password.match?(/\d/)
    errors.add(:password, :missing_special_char, message: 'must include at least one special character') unless password.match?(PASSWORD_SPECIAL_CHAR_REGEX)
  end
end
