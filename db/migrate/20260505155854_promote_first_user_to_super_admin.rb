# frozen_string_literal: true

# Introduce the `super_admin` role and promote the bootstrap user of
# existing installations to it.
#
# Context: prior to this release, the user created via the setup wizard
# was assigned the `account_owner` role, which used to also include the
# installation_configs.manage permission. With this release that
# permission moves to a dedicated `super_admin` role, so the operator of
# every existing installation needs to be promoted to keep their access
# to /settings/admin (Email/Storage/SocialLogin/OpenAI/Channels/Inbound
# Email/Frontend Runtime).
#
# Why this lives in a migration instead of the rbac seed: production
# deploys do NOT run `bin/rails db:seed`. Seeds only run on first install
# via SetupBootstrapService#run_seeds. Migrations, on the other hand, run
# on every deploy via `bin/rails db:migrate`. So creating the role and
# promoting the user from a migration is the only path that reaches
# already-bootstrapped production installations without manual steps.
#
# The "first user" heuristic (oldest created_at) is reliable on the
# Community edition because the install flow only creates a single user
# in the wizard step (advisory lock + User.count > 0 check in
# SetupBootstrapService).
#
# Idempotent: re-runnable without side effects. Fresh installs that run
# the rbac seed afterwards skip the create_or_find here as the role
# already exists; the seed's `find_or_initialize_by` then operates on the
# existing record and the permission set converges.
class PromoteFirstUserToSuperAdmin < ActiveRecord::Migration[7.1]
  def up
    # Ordering caveat: this migration references `users`, `roles`, and
    # `user_roles`, which are created by init_schema (timestamp 9025…) on
    # fresh installs. Because of that far-future timestamp, init_schema
    # actually runs AFTER this migration on a fresh install — so we
    # short-circuit cleanly and let the bootstrap step (which assigns
    # super_admin directly via the seed) handle the fresh case.
    return unless ActiveRecord::Base.connection.table_exists?(:users)
    return unless ActiveRecord::Base.connection.table_exists?(:roles)
    return unless ActiveRecord::Base.connection.table_exists?(:user_roles)
    return unless ActiveRecord::Base.connection.table_exists?(:role_permissions_actions)

    super_admin = ensure_super_admin_role
    sync_super_admin_permissions(super_admin)

    # Strip installation_configs.manage from account_owner so that any
    # operator promoted to account_owner (now or later) does not inherit
    # installation-level access. The bootstrap user keeps the permission
    # via the new super_admin role assigned below. Idempotent.
    revoke_installation_configs_from_account_owner

    first_user = User.order(:created_at).first
    if first_user.nil?
      say 'no users yet — fresh install, bootstrap will assign super_admin', true
      return
    end

    if first_user.user_roles.where(role_id: super_admin.id).exists?
      say "user #{first_user.id} already has super_admin — nothing to do", true
      return
    end

    account_owner = Role.find_by(key: 'account_owner')

    ActiveRecord::Base.transaction do
      if account_owner
        # The user moves from account_owner to super_admin; super_admin already
        # holds every account_owner permission plus installation_configs.manage,
        # so the user gains capabilities and loses none.
        first_user.user_roles.where(role_id: account_owner.id).destroy_all
      end

      first_user.user_roles.create!(role_id: super_admin.id)
    end

    say "promoted user #{first_user.id} (#{first_user.email}) to super_admin", true
  end

  def down
    return unless ActiveRecord::Base.connection.table_exists?(:users)
    return unless ActiveRecord::Base.connection.table_exists?(:roles)
    return unless ActiveRecord::Base.connection.table_exists?(:user_roles)

    super_admin   = Role.find_by(key: 'super_admin')
    account_owner = Role.find_by(key: 'account_owner')
    return unless super_admin && account_owner

    # Restore installation_configs.manage on account_owner so the
    # rollback brings the system back to the previous behaviour.
    unless account_owner.role_permissions_actions.where(permission_key: 'installation_configs.manage').exists?
      account_owner.role_permissions_actions.create!(permission_key: 'installation_configs.manage')
    end

    first_user = User.order(:created_at).first
    if first_user
      ActiveRecord::Base.transaction do
        first_user.user_roles.where(role_id: super_admin.id).destroy_all
        unless first_user.user_roles.where(role_id: account_owner.id).exists?
          first_user.user_roles.create!(role_id: account_owner.id)
        end
      end
    end

    # Drop the super_admin role itself if it's empty (no active assignments).
    super_admin.role_permissions_actions.destroy_all
    super_admin.destroy if super_admin.user_roles.none?
  end

  private

  def ensure_super_admin_role
    role = Role.find_by(key: 'super_admin')
    return role if role

    Role.create!(
      key:         'super_admin',
      name:        'Super Admin',
      description: 'Installation owner — full account access plus installation-level configuration',
      system:      true,
      type:        'user'
    )
  end

  # Grant super_admin every valid permission known to the RBAC config.
  # This keeps the role authoritative regardless of whether the seed has
  # ever run on this install. Idempotent: existing assignments are
  # preserved, missing ones are added.
  def sync_super_admin_permissions(super_admin)
    return unless defined?(ResourceActionsConfig)

    keys = begin
      ResourceActionsConfig.all_permission_keys.select do |key|
        ResourceActionsConfig.valid_permission?(key)
      end
    rescue StandardError => e
      say "could not load ResourceActionsConfig (#{e.class}: #{e.message}) — skipping permission sync", true
      return
    end

    existing = super_admin.role_permissions_actions.pluck(:permission_key).to_set
    missing  = keys.reject { |k| existing.include?(k) }

    missing.each do |permission_key|
      super_admin.role_permissions_actions.create!(permission_key: permission_key)
    end

    say "ensured super_admin has #{keys.size} permissions (#{missing.size} added)", true
  end

  def revoke_installation_configs_from_account_owner
    account_owner = Role.find_by(key: 'account_owner')
    return unless account_owner

    removed = account_owner.role_permissions_actions
                           .where(permission_key: 'installation_configs.manage')
                           .delete_all
    say "revoked installation_configs.manage from account_owner (#{removed} row(s))", true if removed.positive?
  end
end
