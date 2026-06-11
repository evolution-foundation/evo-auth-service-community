# frozen_string_literal: true

require 'rails_helper'

# Regression spec for EVO-1551 — round 2.
# Covers the two bypass vectors Daniel flagged on PR #39:
#   (CB-1.a) gate by key-presence let an agent disable mask_contact_pii by
#            omitting the key and relying on the shallow merge to wipe it.
#   (CB-1.b) Hash#merge replaced sibling keys under `settings` /
#            `custom_attributes`, so any partial PATCH dropped unrelated keys.
#
# These specs exercise the previously-untested paths that the manual smoke
# missed (PATCH without the key; partial custom_attributes update).
RSpec.describe 'PATCH /api/v1/account — mask_contact_pii enforcement (EVO-1551)', type: :request do
  let(:password) { 'Test123!@' }

  # Seeded roles already exist in the auth DB:
  #   - 'agent' (type=account) — non-admin from the controller's perspective
  #   - 'super_admin' (type=user) — admin per ADMIN_ROLE_KEYS in the controller
  # Reuse them instead of trying to create new ones (unique key constraint).
  let(:agent_role) { Role.find_by!(key: 'agent') }
  let(:admin_role) { Role.find_by!(key: 'super_admin') }

  let(:agent_user) do
    user = User.create!(
      name: 'Agent User',
      email: "agent-#{SecureRandom.hex(4)}@example.com",
      password: password,
      password_confirmation: password,
      confirmed_at: Time.current
    )
    UserRole.create!(user: user, role: agent_role)
    user
  end

  let(:admin_user) do
    user = User.create!(
      name: 'Admin User',
      email: "admin-#{SecureRandom.hex(4)}@example.com",
      password: password,
      password_confirmation: password,
      confirmed_at: Time.current
    )
    UserRole.create!(user: user, role: admin_role)
    user
  end

  let(:agent_token) { AccessToken.create!(owner: agent_user, name: 'agent-token', scopes: 'default') }
  let(:admin_token) { AccessToken.create!(owner: admin_user, name: 'admin-token', scopes: 'default') }

  let(:agent_headers) { { 'api_access_token' => agent_token.token, 'Host' => 'localhost' } }
  let(:admin_headers) { { 'api_access_token' => admin_token.token, 'Host' => 'localhost' } }

  before do
    allow(Licensing::Runtime).to receive(:context).and_return(
      instance_double(Licensing::RuntimeContext, active?: true, track_message: nil)
    )

    RuntimeConfig.set('account', {
      'id' => 1,
      'name' => 'Acme',
      'settings' => {
        'mask_contact_pii' => true,
        'audio_transcription' => true
      },
      'custom_attributes' => { 'existing' => 'value' }
    })
  end

  describe 'CB-1.a — gate uses effective change, not key presence' do
    it 'agent PATCH without mask_contact_pii preserves the flag (no shallow-merge wipe)' do
      patch '/api/v1/account',
            params: { account: { settings: { audio_transcription: false } } },
            headers: agent_headers,
            as: :json

      expect(response).to have_http_status(:ok)
      expect(RuntimeConfig.account.dig('settings', 'mask_contact_pii')).to be(true)
      expect(RuntimeConfig.account.dig('settings', 'audio_transcription')).to be(false)
    end

    it 'agent PATCH that flips mask_contact_pii is rejected with 403' do
      patch '/api/v1/account',
            params: { account: { settings: { mask_contact_pii: false } } },
            headers: agent_headers,
            as: :json

      expect(response).to have_http_status(:forbidden)
      expect(RuntimeConfig.account.dig('settings', 'mask_contact_pii')).to be(true)
    end

    it 'agent PATCH that re-asserts the same value is allowed (no effective change)' do
      patch '/api/v1/account',
            params: { account: { settings: { mask_contact_pii: true } } },
            headers: agent_headers,
            as: :json

      expect(response).to have_http_status(:ok)
      expect(RuntimeConfig.account.dig('settings', 'mask_contact_pii')).to be(true)
    end

    it 'admin PATCH that flips mask_contact_pii is accepted' do
      patch '/api/v1/account',
            params: { account: { settings: { mask_contact_pii: false } } },
            headers: admin_headers,
            as: :json

      expect(response).to have_http_status(:ok)
      expect(RuntimeConfig.account.dig('settings', 'mask_contact_pii')).to be(false)
    end
  end

  describe 'CB-1.b — deep merge preserves sibling keys' do
    it 'partial custom_attributes PATCH does not wipe pre-existing keys' do
      patch '/api/v1/account',
            params: { account: { custom_attributes: { 'new_key' => 'new_value' } } },
            headers: admin_headers,
            as: :json

      expect(response).to have_http_status(:ok)
      attrs = RuntimeConfig.account['custom_attributes']
      expect(attrs).to include('existing' => 'value', 'new_key' => 'new_value')
    end

    it 'partial settings PATCH does not wipe other settings' do
      patch '/api/v1/account',
            params: { account: { settings: { audio_transcription: false } } },
            headers: admin_headers,
            as: :json

      expect(response).to have_http_status(:ok)
      settings = RuntimeConfig.account['settings']
      expect(settings).to include('mask_contact_pii' => true, 'audio_transcription' => false)
    end
  end
end
