# frozen_string_literal: true

# Data-migration side of the CRM-99 write consolidation (slice 1).
#
# resource_actions_config.rb dropped the granular create/update keys of the 22
# consolidated resources in favor of the coarse `write` (EVO-2127). Stored
# grants in role_permissions_actions still carry the granular keys. Runtime
# enforcement survives through User::LEGACY_WRITE_ALIASES, but the role editor
# does not: it filters the current selection through the live catalog before
# saving, so any role still holding `<r>.create`/`<r>.update` would lose its
# write on the first save — a silent revocation. Rewriting the stored grants is
# the actual transition mechanism; the alias stays as a safety net for rows
# created between deploy and migrate.
#
# Escalation note: a role holding only one of create/update ends up with the
# full `write`. That promotion is inherent to the consolidation and was accepted
# on the card; the per-role audit that lists who is promoted runs before deploy
# (see the card's AC4 survey).
class ConsolidateWriteGrants < ActiveRecord::Migration[7.1]
  TABLE = 'role_permissions_actions'

  # Snapshot of ResourceActionsConfig::CONSOLIDATED_WRITE_RESOURCES at slice 1.
  # Hardcoded on purpose: later slices will grow the constant, and referencing
  # it here would retroactively change what this migration does.
  RESOURCES = %w[
    labels teams pipelines pipeline_stages products webhooks working_hours
    dashboard_apps custom_attribute_definitions custom_filters canned_responses
    message_templates crm_forms chat_pages csat_survey_responses
    ai_api_keys ai_integration_credentials
    google_authorizations microsoft_authorizations instagram_authorizations
    twitter_authorizations whatsapp_authorizations
  ].freeze

  def up
    # Fresh installs hit this migration before init_schema has run.
    return unless connection.table_exists?(TABLE)

    RESOURCES.each do |resource|
      %w[create update].each do |action|
        old_key = "#{resource}.#{action}"
        new_key = "#{resource}.write"

        # a) Drop stale rows where the role already holds the target key —
        #    the unique index is on (role_id, permission_key), so updating them
        #    would collide. Processing create before update also makes the pair
        #    collapse onto a single write row.
        execute(ActiveRecord::Base.sanitize_sql_array([
          "DELETE FROM #{TABLE} WHERE permission_key = ? " \
          "AND role_id IN (SELECT role_id FROM #{TABLE} WHERE permission_key = ?)",
          old_key, new_key
        ]))
        # b) Rename the remaining rows (these roles lack the target key).
        execute(ActiveRecord::Base.sanitize_sql_array([
          "UPDATE #{TABLE} SET permission_key = ?, updated_at = now() WHERE permission_key = ?",
          new_key, old_key
        ]))
      end
    end
  end

  def down
    # Non-reversible: splitting `write` back into create/update would have to
    # invent which of the two each role originally held. Re-run db/seeds/rbac.rb
    # to repair seeded roles after a rollback.
  end
end
