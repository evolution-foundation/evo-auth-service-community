# frozen_string_literal: true

require 'rails_helper'

# EVO-2062. The installation owner's grant set is an INVARIANT, not a preference:
# RbacGrantReconciler converges it against the whole permission catalog on every
# container boot (docker-entrypoint.sh). Before this guard the role editor listed
# `super_admin` (GET /roles returns Role.all to a super_admin), accepted an edit
# with 200, persisted it — and the next deploy silently reverted it, with no
# signal in the UI, the API or the logs. That is the "checkbox that lies" the RBAC
# work exists to remove, so the write is refused at the endpoint instead.
RSpec.describe 'PUT /api/v1/roles/:id/bulk_update_permissions (installation owner is immutable)', type: :request do
  let(:password) { 'Test123!@' }

  def build_user(name)
    User.create!(
      name: name,
      email: "#{name.parameterize}-#{SecureRandom.hex(4)}@example.com",
      password: password,
      password_confirmation: password,
      confirmed_at: Time.current
    )
  end

  def role_with(*permission_keys, type: 'account', key: "role-#{SecureRandom.hex(4)}")
    role = Role.create!(key: key, name: key.titleize, type: type, system: false)
    permission_keys.each { |pk| role.role_permissions_actions.create!(permission_key: pk) }
    role
  end

  def headers_for(user)
    token = AccessToken.create!(owner: user, name: "tk-#{SecureRandom.hex(3)}", scopes: 'default')
    { 'api_access_token' => token.token, 'Host' => 'localhost' }
  end

  def bulk_update(role, keys, as_user)
    put "/api/v1/roles/#{role.id}/bulk_update_permissions",
        params: { permission_keys: keys },
        headers: headers_for(as_user),
        as: :json
  end

  before do
    allow(Licensing::Runtime).to receive(:context).and_return(
      instance_double(Licensing::RuntimeContext, active?: true, track_message: nil)
    )
  end

  # Only a super_admin can reach the endpoint for a `type: 'user'` role at all
  # (`enforce_role_scope!`), so the caller here is the installation owner itself.
  let!(:installation_owner_role) do
    role_with(
      'roles.bulk_update_permissions',
      'installation_configs.manage',
      'contacts.read',
      type: 'user',
      key: RbacGrantReconciler::ROLE_KEY
    )
  end

  let(:owner) do
    build_user('Installation Owner').tap { |u| UserRole.create!(user: u, role: installation_owner_role) }
  end

  it '403s an attempt to narrow the installation owner instead of accepting a write the boot would revert' do
    bulk_update(installation_owner_role, %w[contacts.read], owner)

    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body.dig('error', 'message')).to match(/invariant/i)
  end

  it 'leaves the grant set untouched after the refused edit' do
    before_keys = installation_owner_role.permission_keys.sort

    bulk_update(installation_owner_role, %w[contacts.read], owner)

    expect(installation_owner_role.reload.permission_keys.sort).to eq(before_keys)
    expect(installation_owner_role.permission_keys).to include('installation_configs.manage')
  end

  it 'still lets the same admin edit any other role (the guard is scoped, not a blanket block)' do
    delegated = role_with('contacts.read', type: 'account')

    bulk_update(delegated, %w[contacts.read contacts.create], owner)

    expect(response).to have_http_status(:ok)
    expect(delegated.reload.permission_keys).to include('contacts.create')
  end
end
