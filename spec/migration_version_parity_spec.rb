# frozen_string_literal: true

require 'rails_helper'

# EVO-2090 — collision-free migration versions.
#
# evo-auth-service-community and evo-ai-crm-community run as SEPARATE apps but
# point at the SAME database, sharing ONE `schema_migrations` table. If both ever
# create a migration with the same version (14-digit timestamp), Rails records it
# once and SKIPS the second app's migration forever -> missing DDL -> boot crash
# (this is what broke `messages.source`, EVO-1911).
#
# To make a collision IMPOSSIBLE BY CONSTRUCTION -- no shared-table split, no
# separate database, no cross-repo CI -- each app owns a DISJOINT slice of the
# version space by PARITY:
#
#   * auth (this repo) -> ODD  versions  (...1, ...3, ...5, ...7, ...9)
#   * CRM              -> EVEN versions  (...0, ...2, ...4, ...6, ...8)
#
# odd and even are disjoint, so the two apps can never pick the same version.
# Each repo enforces its OWN parity locally (this spec), catching a bad migration
# in the PR that introduces it -- no access to the other repo required.
#
# Migrations created before this convention are grandfathered via CUTOFF.
RSpec.describe 'Migration version parity (EVO-2090)' do
  # The convention takes effect from this timestamp. A migration whose version is
  # >= CUTOFF must be ODD; anything older predates the rule and is exempt.
  let(:cutoff) { 20_260_713_000_000 }

  def migration_versions
    Dir[Rails.root.join('db/migrate/*.rb')]
      .map { |path| File.basename(path)[/\A\d{14}/]&.to_i }
      .compact
  end

  it 'finds migrations (guards against a broken glob / wrong path)' do
    expect(migration_versions).not_to be_empty
  end

  # auth owns ODD versions; CRM owns EVEN. Any EVEN version at/after the cutoff can
  # collide with a CRM migration in the shared schema_migrations table.
  it 'every migration created under the convention (version >= CUTOFF) uses an ODD version' do
    offenders = migration_versions.select { |version| version >= cutoff && version.even? }

    expect(offenders).to be_empty, <<~MSG
      Migration version collision guard (EVO-2090): this repo (auth) owns ODD
      migration versions; CRM owns EVEN. The versions below are EVEN and >= the
      convention cutoff (#{cutoff}), so they can collide with a CRM migration in
      the shared `schema_migrations` table:

        #{offenders.sort.join("\n        ")}

      Fix: bump the migration timestamp by 1 second so its version becomes odd.
    MSG
  end

  it 'the rule is active — an even version at/after the cutoff would be flagged' do
    # Sanity: proves the predicate actually rejects even versions in-range, so a
    # green suite means the real check above is meaningful (not vacuously true).
    even_in_range = [cutoff, cutoff + 2]
    expect(even_in_range.select { |version| version >= cutoff && version.even? }).to eq(even_in_range)
    expect((cutoff + 1)).to be_odd
  end
end
