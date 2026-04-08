# frozen_string_literal: true

class SetupBootstrapService
  class AlreadyBootstrappedError < StandardError; end

  def self.call(first_name:, last_name:, email:, password:, client_ip: nil)
    new(first_name:, last_name:, email:, password:, client_ip:).call
  end

  def initialize(first_name:, last_name:, email:, password:, client_ip: nil)
    @first_name = first_name
    @last_name  = last_name
    @email      = email
    @password   = password
    @client_ip  = client_ip
  end

  def call
    run_seeds

    result = ActiveRecord::Base.transaction do
      # Advisory lock prevents concurrent bootstrap attempts
      ActiveRecord::Base.connection.execute("SELECT pg_advisory_xact_lock(#{BOOTSTRAP_LOCK_KEY})")
      raise AlreadyBootstrappedError, 'Installation already completed' if User.count > 0

      ensure_account_config
      user      = create_user
      assign_global_role(user)

      { user: user }
    end

    activate_licensing(result[:user])
    result
  end

  BOOTSTRAP_LOCK_KEY = 73_829_104 # arbitrary fixed key for pg_advisory_xact_lock

  private

  def run_seeds
    load Rails.root.join('db', 'seeds.rb')
  end

  def ensure_account_config
    return if RuntimeConfig.account

    RuntimeConfig.set('account', {
      id:            SecureRandom.uuid,
      name:          'Evolution Community',
      domain:        'localhost',
      support_email: @email,
      locale:        'en',
      status:        'active',
      features:      {},
      settings:      {},
      custom_attributes: {}
    })
  end

  def create_user
    User.create!(
      name:                  "#{@first_name} #{@last_name}",
      email:                 @email,
      password:              @password,
      password_confirmation: @password,
      provider:              'email',
      uid:                   @email,
      availability:          :online,
      mfa_method:            :disabled,
      confirmed_at:          Time.current,
      type:                  'User'
    )
  end

  def assign_global_role(user)
    role = Role.find_by!(key: 'account_owner')
    UserRole.assign_role_to_user(user, role) unless user.has_role?('account_owner')
  end

  def create_oauth_app
    redirect_uri = ENV.fetch('OAUTH_REDIRECT_URI', 'http://localhost:5173/oauth/callback')

    OauthApplication.create!(
      name:         'Default OAuth App',
      uid:          SecureRandom.uuid,
      secret:       Doorkeeper::OAuth::Helpers::UniqueToken.generate,
      redirect_uri: redirect_uri,
      scopes:       'read write admin',
      confidential: false,
      trusted:      true
    )
  end

  def activate_licensing(user)
    store       = Licensing::Store.new
    instance_id = store.load_or_create_instance_id

    Licensing::Setup.perform(
      email:       user.email,
      name:        user.name,
      instance_id: instance_id,
      version:     Licensing::Activation::VERSION,
      client_ip:   @client_ip
    )
  rescue StandardError => e
    Rails.logger.warn "[SetupBootstrap] Licensing activation failed (will retry on first login): #{e.message}"
  end
end
