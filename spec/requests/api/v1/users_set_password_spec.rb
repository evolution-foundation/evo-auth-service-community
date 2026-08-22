# frozen_string_literal: true

require 'rails_helper'

# CRM-210 — the endpoint needs BOTH users.reset_password and users.manage, and
# refuses three targets outright: yourself, a super_admin you do not outrank,
# and a password the model rejects.
RSpec.describe 'Users set_password (CRM-210)', type: :request do
  # Roles come from data migrations, which a schema-loaded database never runs.
  before { load Rails.root.join('db/seeds/rbac.rb') }

  let(:password) { 'Test123!@' }
  let(:new_password) { 'Brand123!@' }
  let(:admin_role) { Role.find_by!(key: 'super_admin') }

  # Everything administrative EXCEPT the new key — proves users.manage alone
  # does not confer account takeover.
  let(:manager_without_key) do
    role = Role.create!(key: "mgr-#{SecureRandom.hex(4)}", name: 'Manager', type: 'account')
    %w[users.read users.update users.manage].each do |key|
      role.role_permissions_actions.create!(permission_key: key)
    end
    role
  end

  # Holds the new key but NOT users.manage — proves the fine key alone is not
  # enough either (administrative_action? demands manage on top).
  let(:resetter_without_manage) do
    role = Role.create!(key: "rst-#{SecureRandom.hex(4)}", name: 'Resetter', type: 'account')
    %w[users.read users.reset_password].each do |key|
      role.role_permissions_actions.create!(permission_key: key)
    end
    role
  end

  let(:full_role) do
    role = Role.create!(key: "full-#{SecureRandom.hex(4)}", name: 'Full', type: 'account')
    %w[users.read users.update users.manage users.reset_password].each do |key|
      role.role_permissions_actions.create!(permission_key: key)
    end
    role
  end

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

  def set_password_for(target, caller_user, body = { password: new_password, password_confirmation: new_password })
    post "/api/v1/users/#{target.id}/set_password", params: body, headers: headers_for(caller_user), as: :json
  end

  let(:target_user) { build_user('Target User') }

  describe 'authorization' do
    it 'denies a caller with users.manage but without users.reset_password' do
      set_password_for(target_user, build_user('Manager', role: manager_without_key))

      expect(response).to have_http_status(:forbidden)
      expect(target_user.reload.valid_password?(new_password)).to be(false)
    end

    it 'denies a caller with users.reset_password but without users.manage' do
      set_password_for(target_user, build_user('Resetter', role: resetter_without_manage))

      expect(response).to have_http_status(:forbidden)
      expect(target_user.reload.valid_password?(new_password)).to be(false)
    end

    it 'allows a caller holding both keys' do
      set_password_for(target_user, build_user('Full Admin', role: full_role))

      expect(response).to have_http_status(:ok)
      expect(target_user.reload.valid_password?(new_password)).to be(true)
    end
  end

  describe 'guards' do
    it 'refuses to set your own password' do
      admin = build_user('Self Admin', role: admin_role)

      set_password_for(admin, admin)

      expect(response).to have_http_status(:forbidden)
      expect(admin.reload.valid_password?(new_password)).to be(false)
    end

    # Anti-escalation: an account-level admin must not be able to take over the
    # installation's top account.
    it 'refuses to set a super_admin password when the caller is not one' do
      victim = build_user('Super Victim', role: admin_role)

      set_password_for(victim, build_user('Full Admin', role: full_role))

      expect(response).to have_http_status(:forbidden)
      expect(victim.reload.valid_password?(new_password)).to be(false)
    end

    it 'allows a super_admin to set another super_admin password' do
      victim = build_user('Super Victim', role: admin_role)

      set_password_for(victim, build_user('Super Caller', role: admin_role))

      expect(response).to have_http_status(:ok)
      expect(victim.reload.valid_password?(new_password)).to be(true)
    end

    it 'rejects a mismatched confirmation' do
      set_password_for(target_user, build_user('Full Admin', role: full_role),
                       { password: new_password, password_confirmation: 'Other123!@' })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(target_user.reload.valid_password?(new_password)).to be(false)
    end

    # The target guards come first: a caller that may not touch this user must
    # get 403, not a 422 teaching it the password policy before the refusal.
    it 'refuses your own card before looking at the password' do
      admin = build_user('Self Admin', role: admin_role)

      set_password_for(admin, admin, { password: '', password_confirmation: '' })

      expect(response).to have_http_status(:forbidden)
    end

    it 'refuses a super_admin target before looking at the password' do
      victim = build_user('Super Victim', role: admin_role)

      set_password_for(victim, build_user('Full Admin', role: full_role),
                       { password: 'weak', password_confirmation: 'other' })

      expect(response).to have_http_status(:forbidden)
      expect(victim.reload.valid_password?(password)).to be(true)
    end

    # Admins do not get to bypass the model's complexity rule.
    it 'rejects a weak password' do
      set_password_for(target_user, build_user('Full Admin', role: full_role),
                       { password: 'weak', password_confirmation: 'weak' })

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'session invalidation' do
    # Doorkeeper::AccessToken is a login session; the app's own AccessToken is an
    # integration API key. Only the session dies with the reset.
    it "revokes the target's login sessions so a stolen one dies with the reset" do
      target = build_user('Session Target')
      # oauth_access_tokens.application_id is NOT NULL, so a session always
      # belongs to an application — same shape AuthHelper#create_access_token builds.
      app = OauthApplication.create!(name: "app-#{SecureRandom.hex(3)}", redirect_uri: 'https://localhost/callback', scopes: 'read write')
      session = Doorkeeper::AccessToken.create!(application: app, resource_owner_id: target.id,
                                                scopes: 'read write', expires_in: 3600)

      set_password_for(target, build_user('Full Admin', role: full_role))

      expect(response).to have_http_status(:ok)
      expect(session.reload.revoked_at).to be_present
      expect(Doorkeeper::AccessToken.where(resource_owner_id: target.id, revoked_at: nil)).to be_empty
      expect(response.parsed_body.dig('data', 'revoked_sessions')).to be >= 1
    end

    it 'leaves the integration API keys alone' do
      target = build_user('Api Key Target')
      api_key = AccessToken.create!(owner: target, name: 'integration', scopes: 'default')

      set_password_for(target, build_user('Full Admin', role: full_role))

      expect(response).to have_http_status(:ok)
      expect(AccessToken.exists?(api_key.id)).to be(true)
    end
  end
end
