# frozen_string_literal: true

require 'rails_helper'

# Story RBAC 2.4 (FR18/NFR4) — a system role's IDENTITY is immutable (key/name)
# and the role is undeletable; custom roles with assigned users cannot be
# deleted either. The guards already exist (roles_controller#update/#destroy +
# Role#prevent_system_role_*); this spec locks grant AND deny of each gate so a
# remapped or stuck gate cannot pass silently.
#
# EVO-2152 (PM ruling — Option A): a system role's permission SET is immutable too
# (folded into FR18). bulk_update_permissions now 403s for EVERY system role — not
# just the installation owner — mirroring the licensing gem. Custom roles stay fully
# editable. Viewing is never blocked (immutable, not invisible): show/index unchanged.
RSpec.describe 'Roles system protection', type: :request do
  let(:password) { 'Test123!@' }
  let(:admin_role) { Role.find_by!(key: 'super_admin') }
  let(:system_role) { Role.find_by!(key: 'agent') }

  def build_user(name, role: nil)
    user = User.create!(
      name: name,
      email: "#{name.parameterize}-#{SecureRandom.hex(4)}@example.com",
      password: password,
      password_confirmation: password,
      confirmed_at: Time.current
    )
    UserRole.create!(user: user, role: role) if role
    user
  end

  def headers_for(user)
    token = AccessToken.create!(owner: user, name: "tk-#{SecureRandom.hex(3)}", scopes: 'default')
    { 'api_access_token' => token.token, 'Host' => 'localhost' }
  end

  let(:admin_user) { build_user('Admin User', role: admin_role) }

  # Every `let` below resolves a SEEDED role by key, so the spec needs the RBAC
  # seed loaded. It never had it: on a clean database all 7 examples died on
  # `Couldn't find Role [key = 'super_admin']`, which is why the file sits in the
  # `--exclude-pattern` of test.yml and why nothing it claims to lock was ever
  # actually locked. Loading the seed per example (the convention the db/migrate
  # specs already use — transactional fixtures roll it back) makes the file
  # self-sufficient, so it can come off that list.
  before { load Rails.root.join('db/seeds/rbac.rb') }

  before do
    allow(Licensing::Runtime).to receive(:context).and_return(
      instance_double(Licensing::RuntimeContext, active?: true, track_message: nil)
    )

    RuntimeConfig.set('account', {
      'id' => 1,
      'name' => 'Acme',
      'settings' => { 'mask_contact_pii' => true },
      'custom_attributes' => {}
    })
  end

  describe 'PATCH /api/v1/roles/:id on a system role' do
    it 'denies changing the name even for a super_admin (deny)' do
      original = system_role.name
      patch "/api/v1/roles/#{system_role.id}",
            params: { name: 'Hacked' }, headers: headers_for(admin_user), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(response.body).to include('Cannot modify key or name of a system role')
      expect(system_role.reload.name).to eq(original)
    end

    it 'still allows updating the description (the gate is narrow — grant)' do
      patch "/api/v1/roles/#{system_role.id}",
            params: { description: 'Atende conversas do dia a dia' },
            headers: headers_for(admin_user), as: :json

      expect(response).to have_http_status(:ok)
      expect(system_role.reload.description).to eq('Atende conversas do dia a dia')
    end
  end

  describe 'DELETE /api/v1/roles/:id' do
    it 'denies deleting a system role even for a super_admin (deny)' do
      delete "/api/v1/roles/#{system_role.id}", headers: headers_for(admin_user)

      expect(response).to have_http_status(:forbidden)
      expect(response.body).to include('Cannot delete system roles')
      expect(Role.exists?(system_role.id)).to be(true)
    end

    it 'denies deleting a custom role that still has assigned users (deny)' do
      custom = Role.create!(key: "temp-#{SecureRandom.hex(4)}", name: 'Temp', type: 'account')
      member = build_user('Member User', role: custom)

      delete "/api/v1/roles/#{custom.id}", headers: headers_for(admin_user)

      expect(response).to have_http_status(:forbidden)
      expect(response.body).to include('Cannot delete role with assigned users')
      expect(Role.exists?(custom.id)).to be(true)
      expect(member.reload.roles).to include(custom)
    end

    it 'deletes an unused custom role (grant)' do
      custom = Role.create!(key: "temp-#{SecureRandom.hex(4)}", name: 'Temp', type: 'account')

      delete "/api/v1/roles/#{custom.id}", headers: headers_for(admin_user)

      expect(response).to have_http_status(:ok)
      expect(Role.exists?(custom.id)).to be(false)
    end
  end

  # EVO-2152: the permission set of a system role is immutable; a custom role's is not.
  describe 'PUT /api/v1/roles/:id/bulk_update_permissions' do
    it 'denies retuning a system role even for a super_admin (deny)' do
      before_keys = system_role.reload.permission_keys

      put "/api/v1/roles/#{system_role.id}/bulk_update_permissions",
          params: { permission_keys: %w[ai_agents.read ai_agents.write] },
          headers: headers_for(admin_user)

      expect(response).to have_http_status(:forbidden)
      expect(response.body).to include('permission set of a system role')
      expect(system_role.reload.permission_keys).to match_array(before_keys) # unchanged
    end

    it 'still lets a super_admin retune a CUSTOM role (grant — the guard is narrow)' do
      custom = Role.create!(key: "custom-#{SecureRandom.hex(4)}", name: 'Custom', type: 'account')

      put "/api/v1/roles/#{custom.id}/bulk_update_permissions",
          params: { permission_keys: %w[ai_agents.read] },
          headers: headers_for(admin_user)

      expect(response).to have_http_status(:ok)
      expect(custom.reload.permission_keys).to eq(%w[ai_agents.read])
    end
  end
end
