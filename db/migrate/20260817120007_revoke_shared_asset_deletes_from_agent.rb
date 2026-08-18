# frozen_string_literal: true

# Paired data-migration for CRM-190 — the attendance role must not delete shared
# account assets. Follow-up to CRM-182 (same rule, four keys that were not in its
# enumerated list).
#
# The default `agent` seed still granted the delete of shared, account-wide assets:
#   - labels.delete            — deleting a label removes it from EVERY conversation
#                                it tagged (labels_controller#destroy).
#   - macros.delete            — deletes a team macro (macros_controller#destroy).
#   - canned_responses.delete  — deletes a team quick-reply (canned_responses#destroy).
#   - message_templates.delete — deletes a message template (message_templates#destroy,
#                                message_template_policy).
# Each key gates ONLY its own destroy action (verified: no attendance side-effect,
# unlike CRM-182's contacts.delete/teams.update). read/create/update and
# macros.execute stay — creating, editing and running are attendance.
#
# macros.delete carries a CRM-side carve-out: Macro#set_visibility forces `personal`
# for every non-admin, so a macro an agent creates belongs to that agent alone and
# its owner may delete it without the key (MacrosController#check_destroy_permission!).
# Revoking the key here removes only the power to delete GLOBAL, shared macros.
#
# Why a data-migration and not seed-only: db/seeds/rbac.rb `destroy_all`s and
# recreates the agent role from the trimmed array on every run, and db:seed runs on
# every deploy. But an install that runs `db:migrate` WITHOUT `db:seed` would keep
# the stale grants — so this migration reconciles the EXISTING system `agent` role.
# Only the system role (key = 'agent') is touched — custom roles are left intact.
#
# ROLLBACK IS FORWARD-ONLY — `down` is a deliberate no-op. Re-granting these keys on
# rollback would be a privilege ESCALATION: a fresh install's agent never held them
# (the CRM-182 migration's re-granting `down` was flagged in review precisely for
# this — not repeated here). Restoring the pre-hardening grant, if ever truly
# needed, is an explicit admin action (and db:seed will NOT do it — the seed no
# longer lists these keys).
class RevokeSharedAssetDeletesFromAgent < ActiveRecord::Migration[7.1]
  AGENT_ROLE_KEY = 'agent'

  REVOKED_PERMISSIONS = %w[
    labels.delete
    macros.delete
    canned_responses.delete
    message_templates.delete
  ].freeze

  def up
    return unless ActiveRecord::Base.connection.table_exists?(:roles)

    role = Role.find_by(key: AGENT_ROLE_KEY)
    return unless role

    role.role_permissions_actions
        .where(permission_key: REVOKED_PERMISSIONS)
        .destroy_all
  end

  # Intentionally a no-op — see the header. Rolling back must NOT re-grant these keys.
  def down; end
end
