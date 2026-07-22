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

    # Idempotent: safe to run on every boot. Returns a summary hash; a no-op
    # (including "role does not exist yet", i.e. pre-bootstrap) reports zeroes
    # instead of raising, so it can never block a container from starting.
    def reconcile!
      target = role
      return { role: nil, added: 0, removed: 0 } unless target

      added = missing_keys(target)
      removed = stale_keys(target)

      ActiveRecord::Base.transaction do
        added.each { |key| target.role_permissions_actions.create!(permission_key: key) }
        target.role_permissions_actions.where(permission_key: removed).destroy_all if removed.any?
      end

      { role: target.key, added: added.size, removed: removed.size }
    end
  end
end
