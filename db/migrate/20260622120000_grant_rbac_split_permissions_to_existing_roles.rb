# frozen_string_literal: true

# Paired data-migration for the RBAC permission split (see tech-spec
# rbac-granular-inbox-permissions).
#
# `users.read` and `inboxes.read` were removed from User::BASIC_READ_PERMISSIONS,
# and `conversations.read_all` was introduced as the opt-in for per-inbox
# scoping. On a fresh install db/seeds/rbac.rb already wires these; existing
# (already-bootstrapped) installations skip the seed, so without this migration
# every role that USED to work only because of the BASIC inheritance would lose
# users.read / inboxes.read on upgrade and break the Conversations screen.
#
# Pattern mirrors AddProductPermissionsToExistingRoles (20260513163200) — same
# idempotency guarantees (SELECT-before-INSERT, no-op when the table/role does
# not exist yet).
#
# What `up` grants:
#   - READ_PERMISSIONS (users.read, inboxes.read, conversations.read_all)
#     -> EVERY existing role. conversations.read_all preserves today's
#        "see all inboxes" behavior; the per-inbox restriction is opt-in and
#        only applies to roles that LACK conversations.read_all.
#   - users.manage (administrative gate) -> account_owner + super_admin AND any
#     custom role that is already administrative (heuristic: it holds
#     users.create OR users.update OR users.delete). This avoids the known
#     regression where a custom "gerente" role that today reaches
#     Settings > Agents via inherited users.read would lose the menu once the
#     frontend gate moves to users.manage.
#
# `down` is intentionally SYMMETRIC: it strips the four keys this migration
# adds, from EVERY role, with no per-role provenance tracking.
#
# ROLLBACK IS LOSSY — `down` does NOT restore a clean prior state, and reverting
# T2.1 (the BASIC_READ_PERMISSIONS change) does NOT repair it:
#   * users.read / inboxes.read — these lived in BASIC before T2.1, so reverting
#     T2.1 restores them globally. The system `agent` also held inboxes.read via
#     the seed; `down` strips it, but the reverted BASIC covers that. OK.
#   * users.manage / conversations.read_all — these NEVER existed in BASIC. They
#     are held legitimately by account_owner/super_admin (and agent, for
#     read_all) via the seed. `down` removes them and NOTHING restores them.
# Therefore a `down` leaves the system roles missing users.manage /
# conversations.read_all until `db/seeds/rbac.rb` is re-run. Re-seeding is the
# supported repair step after any rollback of this migration. This is acceptable
# for a one-way upgrade migration; we deliberately avoid per-role provenance.
class GrantRbacSplitPermissionsToExistingRoles < ActiveRecord::Migration[7.1]
  # Operational reads granted to every existing role.
  READ_PERMISSIONS = %w[
    users.read
    inboxes.read
    conversations.read_all
  ].freeze

  # Administrative gate.
  MANAGE_PERMISSION = 'users.manage'

  # Roles that always receive the administrative gate.
  ADMIN_ROLE_KEYS = %w[account_owner super_admin].freeze

  # A custom role is treated as administrative (and thus eligible for
  # users.manage) when it already manages users via any of these keys.
  ADMIN_HEURISTIC_KEYS = %w[users.create users.update users.delete].freeze

  ALL_ADDED_KEYS = (READ_PERMISSIONS + [MANAGE_PERMISSION]).freeze

  def up
    # Fresh installs hit this migration before init_schema has run, so `roles`
    # may not exist yet — the seed will cover them later.
    return unless ActiveRecord::Base.connection.table_exists?(:roles)

    Role.find_each do |role|
      READ_PERMISSIONS.each do |permission_key|
        grant(role, permission_key)
      end

      grant(role, MANAGE_PERMISSION) if administrative_role?(role)
    end
  end

  def down
    return unless ActiveRecord::Base.connection.table_exists?(:roles)

    Role.find_each do |role|
      role.role_permissions_actions.where(permission_key: ALL_ADDED_KEYS).destroy_all
    end
  end

  private

  def grant(role, permission_key)
    return if role.role_permissions_actions.exists?(permission_key: permission_key)

    role.role_permissions_actions.create!(permission_key: permission_key)
  end

  def administrative_role?(role)
    return true if ADMIN_ROLE_KEYS.include?(role.key)

    role.role_permissions_actions
        .where(permission_key: ADMIN_HEURISTIC_KEYS)
        .exists?
  end
end
