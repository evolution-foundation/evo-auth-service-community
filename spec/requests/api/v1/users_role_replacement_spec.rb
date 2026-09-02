# frozen_string_literal: true

require 'rails_helper'

# CRM-496 — a role update has to REPLACE the previous grant. It revoked only
# `system: false` roles, and every seeded role is system, so it revoked nothing:
# a promotion added a second row, leaving the presented role stale and a
# demotion holding on to the permissions it was meant to remove.
RSpec.describe 'PATCH /api/v1/users/:id — role replacement', type: :request do
  # Roles come from data migrations, which a schema-loaded database never runs.
  before { load Rails.root.join('db/seeds/rbac.rb') }

  let(:password) { 'Test123!@' }

  def build_user(name, role_key: nil)
    user = User.create!(
      name: name,
      email: "#{name.parameterize}-#{SecureRandom.hex(4)}@example.com",
      password: password,
      password_confirmation: password,
      confirmed_at: Time.current
    )
    UserRole.assign_role_to_user(user, Role.find_by!(key: role_key)) if role_key
    user
  end

  def headers_for(user)
    token = AccessToken.create!(owner: user, name: "tk-#{SecureRandom.hex(3)}", scopes: 'default')
    { 'api_access_token' => token.token, 'Host' => 'localhost' }
  end

  def change_role_of(user, role_key)
    patch "/api/v1/users/#{user.id}", params: { role: role_key }, headers: headers_for(admin), as: :json
    expect(response).to have_http_status(:ok)
  end

  let(:admin) { build_user('Role Admin', role_key: 'super_admin') }
  let(:target) { build_user('Role Target', role_key: 'agent') }

  it 'replaces the previous role instead of adding to it' do
    change_role_of(target, 'super_admin')

    expect(target.reload.roles.pluck(:key)).to contain_exactly('super_admin')
  end

  it 'presents the new role on both resolution paths' do
    change_role_of(target, 'super_admin')

    expect(User.find(target.id).role_data[:key]).to eq('super_admin')
    expect(User.includes(user_roles: :role).find(target.id).role_data[:key]).to eq('super_admin')
  end

  it 'drops the permissions the revoked role carried' do
    elevated = build_user('Elevated', role_key: 'super_admin')
    plain_agent = build_user('Plain Agent', role_key: 'agent').all_permissions

    change_role_of(elevated, 'agent')

    expect(User.find(elevated.id).all_permissions).to match_array(plain_agent)
  end

  it 'leaves the derived role the attendance sync owns' do
    derived = Role.create!(key: "evo_derived_#{target.id}_global", name: "Derived #{target.id}", type: 'account')
    UserRole.assign_role_to_user(target, derived)

    change_role_of(target, 'super_admin')

    expect(target.reload.roles.pluck(:key)).to contain_exactly('super_admin', derived.key)
  end
end
