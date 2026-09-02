# frozen_string_literal: true

require 'rails_helper'

RSpec.describe User, type: :model do
  def build_user
    User.create!(
      name: 'Role Data User',
      email: "role-data-#{SecureRandom.hex(4)}@example.com",
      password: 'Valid1!Pass',
      password_confirmation: 'Valid1!Pass',
      confirmed_at: Time.current
    )
  end

  def role_with(key:, type: 'account')
    Role.create!(key: key, name: key.titleize, type: type, system: false)
  end

  def assign(user, role, at: Time.current)
    UserRole.assign_role_to_user(user, role)
    UserRole.where(user: user, role: role).update_all(created_at: at)
  end

  def derived_role_for(user, scope: 'global')
    role_with(key: "evo_derived_#{user.id}_#{scope}")
  end

  def resolved_role_key(user, eager:)
    reloaded = eager ? User.includes(user_roles: :role).find(user.id) : User.find(user.id)
    reloaded.role_data&.fetch(:key)
  end

  [ true, false ].each do |eager|
    context "with user_roles #{eager ? 'eager loaded' : 'resolved by query'}" do
      it 'returns the only role when the user has a single one' do
        user = build_user
        assign(user, role_with(key: 'super_admin'))

        expect(resolved_role_key(user, eager: eager)).to eq('super_admin')
      end

      it 'returns the real role when the derived one was created first' do
        user = build_user
        assign(user, derived_role_for(user), at: 2.days.ago)
        assign(user, role_with(key: 'super_admin'), at: 1.day.ago)

        expect(resolved_role_key(user, eager: eager)).to eq('super_admin')
      end

      it 'returns the real role when the derived one was created last' do
        user = build_user
        assign(user, role_with(key: 'evolution_admin'), at: 2.days.ago)
        assign(user, derived_role_for(user), at: 1.day.ago)

        expect(resolved_role_key(user, eager: eager)).to eq('evolution_admin')
      end

      it 'ignores derived roles of every tenant scope' do
        user = build_user
        assign(user, derived_role_for(user, scope: SecureRandom.uuid), at: 3.days.ago)
        assign(user, derived_role_for(user, scope: 'global'), at: 2.days.ago)
        assign(user, role_with(key: 'account_owner'), at: 1.day.ago)

        expect(resolved_role_key(user, eager: eager)).to eq('account_owner')
      end

      it 'falls back to the derived role when it is the only one' do
        user = build_user
        derived = derived_role_for(user)
        assign(user, derived)

        expect(resolved_role_key(user, eager: eager)).to eq(derived.key)
      end

      # A role update replaces the previous grant, so with two real roles the
      # newest is the one the user holds — the older row is what it replaced.
      it 'resolves the most recent role when both are real' do
        user = build_user
        assign(user, role_with(key: 'agent'), at: 2.days.ago)
        assign(user, role_with(key: 'supervisor'), at: 1.day.ago)

        expect(resolved_role_key(user, eager: eager)).to eq('supervisor')
      end

      it 'breaks a same-instant tie on the key, alike in both branches' do
        user = build_user
        granted_at = 1.day.ago
        assign(user, role_with(key: 'aaa_role'), at: granted_at)
        assign(user, role_with(key: 'zzz_role'), at: granted_at)

        expect(resolved_role_key(user, eager: eager)).to eq('zzz_role')
      end

      it 'returns nil when the user has no role at all' do
        expect(resolved_role_key(build_user, eager: eager)).to be_nil
      end
    end
  end
end
