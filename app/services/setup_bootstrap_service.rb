# frozen_string_literal: true

class SetupBootstrapService
  class AlreadyBootstrappedError < StandardError; end

  def self.call(first_name:, last_name:, email:, password:, client_ip: nil, brand: {})
    new(first_name:, last_name:, email:, password:, client_ip:, brand:).call
  end

  def initialize(first_name:, last_name:, email:, password:, client_ip: nil, brand: {})
    @first_name = first_name
    @last_name  = last_name
    @email      = email
    @password   = password
    @client_ip  = client_ip
    @brand      = brand || {}
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
      assign_enterprise_evolution_admin(user)
      apply_enterprise_whitelabel

      survey_token = generate_survey_token(user)
      { user: user, survey_token: survey_token }
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
    # The bootstrap user is the installation owner — they get `super_admin`,
    # the only role that holds installation_configs.manage and can render the
    # /settings/admin panel. Subsequent users created through the UI keep
    # being assigned `account_owner` (or `agent`) by AgentBuilder.
    role = Role.find_by(key: 'super_admin') || Role.find_by!(key: 'account_owner')
    UserRole.assign_role_to_user(user, role) unless user.has_role?(role.key)
  end

  # The bootstrap user is the installation owner, so in an enterprise deployment
  # they must also be the global `evolution_admin` — otherwise every
  # `/enterprise/v1/admin/*` route returns 403 (the licensing engine resolves
  # roles from `evo_enterprise_tenant_memberships`, NOT from the auth role).
  #
  # The auth service does not load the enterprise gem (no TenantMembership
  # model), but it shares the same `evo_community` database, so we write the
  # global membership with raw SQL. Guarded: a community-only install has no
  # such table, so we skip silently. Idempotent via the partial unique index
  # on (user_id) WHERE tenant_id IS NULL.
  def assign_enterprise_evolution_admin(user)
    conn = ActiveRecord::Base.connection
    table = 'evo_enterprise_tenant_memberships'
    return unless conn.table_exists?(table)

    quoted_id = conn.quote(user.id)
    conn.execute(<<~SQL.squish)
      INSERT INTO #{table} (id, user_id, tenant_id, role, created_at, updated_at)
      VALUES (gen_random_uuid(), #{quoted_id}, NULL, 'evolution_admin', now(), now())
      ON CONFLICT (user_id) WHERE tenant_id IS NULL DO NOTHING
    SQL
    Rails.logger.info "[SetupBootstrap] granted enterprise evolution_admin to #{user.email}"
  rescue StandardError => e
    # Never block the installation if the enterprise grant fails. The non-manual
    # recovery is the org-única net in `evo_enterprise:install` (runs every boot,
    # re-mints the single owner's global membership) — NOT the manual
    # `evo_enterprise:bootstrap_dev`. Logged at ERROR: a miss here leaves the admin
    # without cross-tenant access, and the self-hosted login path has no heal for
    # the global membership (deliberate — see the auth-enterprise login_heal).
    Rails.logger.error "[SetupBootstrap] Failed to grant enterprise evolution_admin: #{e.message}"
  end

  # Persist the operator's box branding captured at /setup onto the single agency's
  # whitelabel row. Mirrors assign_enterprise_evolution_admin: the auth service
  # shares the evo_community DB but does not load the enterprise gem, so we write
  # via guarded, parameterized SQL. Guard skips silently on a community-only
  # install. This is an EXPLICIT operator write (overwrite per field) — only the
  # provided fields are set, so it composes with the install's fill-if-unclaimed
  # default without clobbering unspecified columns.
  def apply_enterprise_whitelabel
    cols = @brand.slice(:app_title, :primary_color, :secondary_color)
                 .select { |_, v| v.present? }
    return if cols.empty?

    conn  = ActiveRecord::Base.connection
    table = 'evo_enterprise_whitelabel_configs'
    return unless conn.table_exists?(table)

    agency_id = conn.select_value('SELECT id FROM evo_enterprise_agencies ORDER BY created_at LIMIT 1')
    return if agency_id.nil?

    insert_primary   = cols[:primary_color] || '#22C55E'
    insert_title     = cols[:app_title] || ''
    insert_secondary = cols[:secondary_color] # may be nil
    set_clause = cols.keys.map { |c| "#{c} = EXCLUDED.#{c}" }.join(', ')

    conn.execute(<<~SQL.squish)
      INSERT INTO #{table}
        (agency_id, primary_color, app_title, secondary_color, smtp_config, email_templates, hide_evo_branding)
      VALUES
        (#{conn.quote(agency_id)}, #{conn.quote(insert_primary)}, #{conn.quote(insert_title)}, #{conn.quote(insert_secondary)}, '{}', '{}', false)
      ON CONFLICT (agency_id) DO UPDATE SET #{set_clause}, updated_at = now()
    SQL
    Rails.logger.info "[SetupBootstrap] applied enterprise whitelabel brand (#{cols.keys.join(', ')})"
  rescue StandardError => e
    Rails.logger.warn "[SetupBootstrap] Failed to apply enterprise whitelabel: #{e.message}"
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

  def generate_survey_token(user)
    token = SecureRandom.hex(32)
    redis_client.set("survey_token:#{token}", user.id, ex: 600) # 10 minutes TTL
    token
  rescue StandardError => e
    Rails.logger.warn "[SetupBootstrap] Failed to generate survey token: #{e.message}"
    nil
  end

  def redis_client
    Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/1'))
  end

  def activate_licensing(user)
    # Best-effort, fully asynchronous: the bootstrap response must never hang
    # waiting for the licensing server. The job retries internally and falls
    # back to the heartbeat-driven reactivation if it cannot reach the server.
    Licensing::SetupJob.perform_later(
      email:     user.email,
      name:      user.name,
      client_ip: @client_ip
    )
  rescue StandardError => e
    Rails.logger.warn "[SetupBootstrap] Failed to enqueue licensing setup: #{e.message}"
  end
end
