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

  it 'flags operationally-implied keys with their source and not as basic' do
    User::OPERATIONAL_IMPLICATIONS.each do |source, implied_keys|
      implied_keys.each do |key|
        next if User::BASIC_READ_PERMISSIONS.include?(key)

        resource, action = key.split('.')
        entry = nested(resource.to_sym, action.to_sym)
        expect(entry[:implied_by]).to eq(source)
        expect(entry[:basic]).to be(false)
      end
    end
  end

  it 'leaves ordinary managed permissions unlocked' do
    entry = nested(:labels, :create)
    expect(entry[:basic]).to be(false)
    expect(entry[:implied_by]).to be_nil
    expect(flat('labels.create')[:basic]).to be(false)
    expect(flat('labels.create')[:implied_by]).to be_nil
  end
end
