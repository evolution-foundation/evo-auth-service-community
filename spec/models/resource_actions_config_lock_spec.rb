# frozen_string_literal: true

require 'rails_helper'

# The role editor must not offer a manageable checkbox for permissions that
# every user holds regardless of the role: BASIC_READ_PERMISSIONS (global) and
# OPERATIONAL_IMPLICATIONS (implied by another grant). api_format exposes
# `basic` / `implied_by` per action so the frontend can lock them.
RSpec.describe ResourceActionsConfig, '.api_format lock metadata' do
  let(:format) { described_class.api_format }

  def nested(resource, action)
    format[:resources][resource][:actions][action]
  end

  def flat(key)
    format[:all_permissions].find { |p| p[:key] == key }
  end

  it 'flags every catalog-present BASIC_READ_PERMISSIONS key as basic' do
    # dashboard.read is basic but has no catalog resource (never rendered in
    # the editor), so it needs no lock; only the keys that DO appear must lock.
    catalog_basic = User::BASIC_READ_PERMISSIONS.select { |k| described_class.valid_permission?(k) }
    expect(catalog_basic).to include('accounts.read', 'labels.read', 'teams.read')

    catalog_basic.each do |key|
      resource, action = key.split('.')
      entry = nested(resource.to_sym, action.to_sym)
      expect(entry[:basic]).to be(true), "expected #{key} basic in nested actions"
      expect(flat(key)[:basic]).to be(true), "expected #{key} basic in all_permissions"
    end
  end

  it 'flags LOCKING_IMPLICATIONS keys with their FIRST implying source and not as basic' do
    # permission_lock_info reports the FIRST source in LOCKING_IMPLICATIONS order.
    # Assert exactly that, so a regression pointing implied_by at the wrong (even
    # if valid) source is caught. Every implied key is a real catalog key, so
    # nested() must resolve it — an implication to a non-catalog key is itself a
    # bug and fails here.
    User::LOCKING_IMPLICATIONS.each do |_source, implied_keys|
      implied_keys.each do |key|
        next if User::BASIC_READ_PERMISSIONS.include?(key)

        expected_source = User::LOCKING_IMPLICATIONS.find { |_s, imp| imp.include?(key) }.first
        resource, action = key.split('.')
        entry = nested(resource.to_sym, action.to_sym)
        expect(entry[:implied_by]).to eq(expected_source)
        expect(entry[:basic]).to be(false)
      end
    end
  end

  # EVO-2127. The coarse write is implied at RUNTIME by every granular write
  # (User::OPERATIONAL_IMPLICATIONS) but must NOT be locked in the editor: it is
  # the grant the Write checkbox decides, and the one that outlives the granular
  # keys. A locked key is dropped from the group the checkbox controls, so the
  # editor could add `<resource>.write` and never remove it — the role would keep
  # a write grant the admin believes they revoked.
  it 'leaves the coarse <resource>.write editable — implied at runtime, never locked' do
    entry = nested(:ai_agents, :write)
    expect(entry[:implied_by]).to be_nil
    expect(entry[:basic]).to be(false)
    expect(flat('ai_agents.write')[:implied_by]).to be_nil

    # ...while the runtime implication that kills the 403 stays in place.
    #
    # EVO-2124 added a SECOND implied key to the same source (ai_agents.<granular
    # write> => ai_agent_processor.execute), so this asserts inclusion, not an
    # exact list: the two maps collide on this source and are concatenated. An
    # `eq` here would fail the moment another runtime implication is hung off a
    # granular write — and, worse, a plain Hash#merge upstream would silently drop
    # the coarse write instead. That is the regression this line guards.
    expect(User::OPERATIONAL_IMPLICATIONS['ai_agents.create']).to include('ai_agents.write')
  end

  it 'locks no coarse write anywhere in the catalog' do
    locked = described_class.all_permission_keys.select do |key|
      key.end_with?('.write') && described_class.permission_lock_info(key)[:implied_by]
    end
    expect(locked).to be_empty, "coarse writes must stay editable, got: #{locked.join(', ')}"
  end

  it 'leaves ordinary managed permissions unlocked' do
    entry = nested(:labels, :create)
    expect(entry[:basic]).to be(false)
    expect(entry[:implied_by]).to be_nil
    expect(flat('labels.create')[:basic]).to be(false)
    expect(flat('labels.create')[:implied_by]).to be_nil
  end
end
