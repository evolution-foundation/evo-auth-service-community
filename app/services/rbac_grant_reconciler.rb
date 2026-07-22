# frozen_string_literal: true

# Keeps the installation-owner role (`super_admin`) aligned with the permission
# catalog.
#
# Why this exists: nothing in the stack bypasses RBAC for the admin. The
# resource gate (`PermissionCheckable#authorize_resource!` -> `User#has_permission?`)
# and the `/permissions` endpoint the frontend consumes are both row-based, and
# the frontend `can()` is purely data-driven. The admin therefore has full
# access ONLY because the seed grants them the whole catalog. Every time the
# catalog grows (a new resource/action), an already-bootstrapped installation
# keeps the old grant set: the backend 403s the admin on the new feature and the
# frontend hides the control — a silent capability loss with no configuration
# error anywhere.
#
# Fresh installs are covered by db/seeds/rbac.rb; existing installations are
# covered by running #reconcile! on every boot (see docker-entrypoint.sh) and by
# the CI guard that fails when the seeded grant set diverges from the catalog.
#
# The reconciliation is deliberately scoped to `super_admin` and is additive
# plus catalog-pruning: it never touches roles an operator may have customised
# through the role editor.
class RbacGrantReconciler
  ROLE_KEY = 'super_admin'

  # The delegated-admin role carries the SAME seed-defined invariant as the
  # installation owner — the whole catalog minus a short exclusion list — and so
  # drifts on catalog growth in exactly the same way. It is deliberately NOT
  # reconciled on boot: unlike super_admin it is editable in the role editor, so
  # rewriting it every deploy would silently revert an operator's customisation.
  # Existing installations therefore still need a paired data migration when the
  # catalog grows. `delegated_missing_keys` exists so that gap is *reported*
  # instead of silent (see docs/rbac-admin-access.md and the runbook).
  # Mirrors `account_owner_exclusive` in db/seeds/rbac.rb — keep the two in sync.
  DELEGATED_ROLE_KEY = 'account_owner'
  DELEGATED_EXCLUSIVES = %w[accounts.stats installation_configs.manage].freeze

  class << self
    def role
      Role.find_by(key: ROLE_KEY)
    end

    def catalog_keys
      ResourceActionsConfig.all_permission_keys.select do |key|
        ResourceActionsConfig.valid_permission?(key)
      end
    end

    def current_keys(target = role)
      return [] unless target

      target.role_permissions_actions.pluck(:permission_key)
    end

    # Catalog entries the role should hold but does not — the silent capability
    # loss this class exists to prevent.
    def missing_keys(target = role)
      catalog_keys - current_keys(target)
    end

    # Grants that no longer exist in the catalog (removed resources/actions).
    # They are inert at check time but keep dead keys visible in the role editor.
    def stale_keys(target = role)
      current_keys(target) - catalog_keys
    end

    def drifted?(target = role)
      return false unless target

      missing_keys(target).any? || stale_keys(target).any?
    end

    def delegated_role
      Role.find_by(key: DELEGATED_ROLE_KEY)
    end

    # Report-only counterpart of `missing_keys` for account_owner. Never written
    # back automatically — see the DELEGATED_ROLE_KEY note above.
    def delegated_missing_keys
      target = delegated_role
      return [] unless target

      (catalog_keys - DELEGATED_EXCLUSIVES) - current_keys(target)
    end

    # Idempotent: safe to run on every boot. Returns a summary hash; a no-op
    # (including "role does not exist yet", i.e. pre-bootstrap) reports zeroes
    # instead of raising, so it can never block a container from starting.
    #
    # The insert goes through `insert_all` with ON CONFLICT DO NOTHING rather
    # than a create! per key. Two replicas booting at the same time compute the
    # same `added` set and race: with create!, the loser hits the unique index
    # (`index_role_perms_actions_unique`), the exception unwinds the whole
    # transaction, and EVERY other grant in the batch is rolled back too — the
    # boot self-heal would leave the installation exactly as drifted as it found
    # it. Conflicts are the expected outcome of a race here, not an error, so
    # they are skipped instead of raised.
    #
    # `insert_all` skips model validations. That is safe (and the point) because
    # every key comes from `catalog_keys`, which is what RolePermissionsAction's
    # permission_key validation checks against anyway. Timestamps are passed
    # explicitly so the rows do not depend on the column defaults.
    def reconcile!
      target = role
      return { role: nil, added: 0, removed: 0 } unless target

      added = missing_keys(target)
      removed = stale_keys(target)

      ActiveRecord::Base.transaction do
        if added.any?
          now = Time.current
          RolePermissionsAction.insert_all(
            added.map do |key|
              { role_id: target.id, permission_key: key, created_at: now, updated_at: now }
            end,
            unique_by: %i[role_id permission_key]
          )
        end
        target.role_permissions_actions.where(permission_key: removed).delete_all if removed.any?
      end

      { role: target.key, added: added.size, removed: removed.size }
    end
  end
end
