# frozen_string_literal: true

class NormalizeLegacySchemaMigrationVersions < ActiveRecord::Migration[7.1]
  # Long-lived installs may have recorded the InitSchema/AddIssuedId
  # migrations under the year-9025 typo timestamps (`90250819224900` /
  # `90250819224901`). The filenames were corrected to `20250819...` but
  # the schema_migrations rows were never updated, so Rails sees the
  # corrected versions as pending and tries to re-run them. InitSchema is
  # fully idempotent, but downstream migrations may not be.
  #
  # This migration normalises those legacy rows so subsequent migrations
  # see a clean state. It is a no-op on fresh installs.
  def up
    return unless legacy_versions_present?

    say_with_time 'Normalizing legacy schema_migration versions' do
      # InitSchema: insert the canonical row if missing, then drop the typo.
      execute <<~SQL
        INSERT INTO schema_migrations (version)
        VALUES ('20250819224900')
        ON CONFLICT (version) DO NOTHING
      SQL
      execute "DELETE FROM schema_migrations WHERE version = '90250819224900'"

      # AddIssuedIdToAccessTokens: same treatment.
      execute <<~SQL
        INSERT INTO schema_migrations (version)
        VALUES ('20250819224901')
        ON CONFLICT (version) DO NOTHING
      SQL
      execute "DELETE FROM schema_migrations WHERE version = '90250819224901'"
    end
  end

  def down
    # Intentional no-op: we never want to revive the typo timestamps.
  end

  private

  def legacy_versions_present?
    select_value(<<~SQL).to_i.positive?
      SELECT COUNT(*) FROM schema_migrations
      WHERE version IN ('90250819224900', '90250819224901')
    SQL
  end
end
