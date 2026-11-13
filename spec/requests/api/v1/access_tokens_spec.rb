# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Access tokens API', type: :request do
  # Roles come from data migrations, which a schema-loaded database never runs.
  before { load Rails.root.join('db/seeds/rbac.rb') }

  let(:user) do
    User.create!(
      name: 'Token Admin',
      email: "token-admin-#{SecureRandom.hex(4)}@example.com",
      password: 'Test123!@',
      password_confirmation: 'Test123!@',
      confirmed_at: Time.current
    ).tap { |u| UserRole.create!(user: u, role: Role.find_by!(key: 'super_admin')) }
  end

  let(:session_token) { AccessToken.create!(owner: user, name: 'session', scopes: 'default') }

  def headers_with(raw)
    { 'api_access_token' => raw, 'Host' => 'localhost' }
  end

  def body
    response.parsed_body['data']
  end

  describe 'token value' do
    it 'is returned on create and never again' do
      post '/api/v1/access_tokens',
           params: { access_token: { name: 'CI', scopes: 'labels.read' } },
           headers: headers_with(session_token.token), as: :json

      expect(response).to have_http_status(:created)
      created = body['access_token']
      expect(created['token']).to match(/\A\h{64}\z/)
      expect(AccessToken.for_token(created['token']).id).to eq(created['id'])

      get '/api/v1/access_tokens', headers: headers_with(session_token.token)
      expect(body.map(&:keys).flatten).not_to include('token')

      get "/api/v1/access_tokens/#{created['id']}", headers: headers_with(session_token.token)
      expect(body['access_token']).not_to have_key('token')
    end

    it 'is returned once more on regenerate, and the old value stops working' do
      target = AccessToken.create!(owner: user, name: 'target', scopes: 'labels.read')
      old_value = target.token

      patch "/api/v1/access_tokens/#{target.id}/update_token", headers: headers_with(session_token.token)

      expect(response).to have_http_status(:ok)
      new_value = body.dig('access_token', 'token')
      expect(new_value).to match(/\A\h{64}\z/)
      expect(new_value).not_to eq(old_value)

      get '/api/v1/profile', headers: headers_with(old_value)
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'scopes' do
    let(:narrow) { AccessToken.create!(owner: user, name: 'narrow', scopes: 'labels.read') }

    it 'stops a token from using what its scopes do not grant, even when the owner may' do
      get '/api/v1/access_tokens', headers: headers_with(narrow.token)
      expect(response).to have_http_status(:forbidden)

      post '/api/v1/access_tokens',
           params: { access_token: { name: 'escalate', scopes: 'default' } },
           headers: headers_with(narrow.token), as: :json
      expect(response).to have_http_status(:forbidden)
      expect(AccessToken.where(name: 'escalate')).to be_empty
    end

    it 'lets a token use what its scopes grant' do
      reader = AccessToken.create!(owner: user, name: 'reader', scopes: 'access_tokens.read')

      get '/api/v1/access_tokens', headers: headers_with(reader.token)

      expect(response).to have_http_status(:ok)
    end

    it 'sends the effective scopes, never the value, to the services that validate the token' do
      post '/api/v1/auth/validate', headers: headers_with(narrow.token)

      expect(response).to have_http_status(:ok)
      token = body['token']
      expect(token).not_to have_key('token')
      expect(token['scopes']).to eq('labels.read')
      expect(token['effective_scopes']).to include('labels.read', 'dashboard.read')
      expect(token['effective_scopes']).not_to include('contacts.read')
    end
  end

  describe "granting scopes with a scoped token" do
    let(:manager) { AccessToken.create!(owner: user, name: "manager", scopes: "access_tokens.create,access_tokens.update,labels.read") }

    it "refuses an unrestricted token or a scope the caller token does not hold" do
      %w[default contacts.read].each do |scopes|
        post "/api/v1/access_tokens",
             params: { access_token: { name: "child", scopes: scopes } },
             headers: headers_with(manager.token), as: :json

        expect(response).to have_http_status(:forbidden), scopes
      end
      expect(AccessToken.where(name: "child")).to be_empty
    end

    it "grants a scope the caller token holds" do
      post "/api/v1/access_tokens",
           params: { access_token: { name: "child", scopes: "labels.read" } },
           headers: headers_with(manager.token), as: :json

      expect(response).to have_http_status(:created)
    end

    it "refuses to widen a token beyond the caller token" do
      target = AccessToken.create!(owner: user, name: "target", scopes: "labels.read")

      patch "/api/v1/access_tokens/#{target.id}",
            params: { access_token: { scopes: "default" } },
            headers: headers_with(manager.token), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(target.reload.scopes).to eq("labels.read")
    end
  end

  describe "validation after a scope change" do
    it "serves the new scopes without waiting for the cache to expire" do
      token = AccessToken.create!(owner: user, name: "changing", scopes: "labels.read,contacts.read")
      post "/api/v1/auth/validate", headers: headers_with(token.token)
      expect(body.dig("token", "effective_scopes")).to include("contacts.read")

      token.update!(scopes: "labels.read")
      post "/api/v1/auth/validate", headers: headers_with(token.token)

      expect(body.dig("token", "effective_scopes")).not_to include("contacts.read")
    end
  end

  describe "permission check endpoint" do
    let(:agent) do
      User.create!(
        name: "Agent", email: "agent-#{SecureRandom.hex(4)}@example.com",
        password: "Test123!@", password_confirmation: "Test123!@", confirmed_at: Time.current
      )
    end

    it "grants only what both the token scopes and the owner allow" do
      unrestricted = AccessToken.create!(owner: agent, name: "agent-default", scopes: "default")
      post "/api/v1/permissions/check", params: { permission_key: "users.manage" }, headers: headers_with(unrestricted.token), as: :json
      expect(body["has_permission"]).to be(false)

      narrow = AccessToken.create!(owner: user, name: "admin-narrow", scopes: "labels.read")
      post "/api/v1/permissions/check", params: { permission_key: "contacts.read" }, headers: headers_with(narrow.token), as: :json
      expect(body["has_permission"]).to be(false)
      post "/api/v1/permissions/check", params: { permission_key: "labels.read" }, headers: headers_with(narrow.token), as: :json
      expect(body["has_permission"]).to be(true)
    end
  end

  describe 'audit trail' do
    it 'logs who created, regenerated and deleted a token, without the value' do
      lines = []
      allow(Rails.logger).to receive(:warn).and_wrap_original { |m, msg| lines << msg.to_s; m.call(msg) }

      post '/api/v1/access_tokens',
           params: { access_token: { name: 'audited', scopes: 'labels.read' } },
           headers: headers_with(session_token.token), as: :json
      created = body['access_token']
      patch "/api/v1/access_tokens/#{created['id']}/update_token", headers: headers_with(session_token.token)
      regenerated = body.dig('access_token', 'token')
      delete "/api/v1/access_tokens/#{created['id']}", headers: headers_with(session_token.token)

      audit = lines.grep(/\[AccessTokens#/)
      expect(audit.map { |l| l[/\[AccessTokens#(\w+)\]/, 1] }).to eq(%w[create update_token destroy])
      expect(audit).to all(include("via=access_token"))
      expect(audit).to all(include("actor=#{user.id}", "token=#{created['id']}"))
      expect(audit.join).not_to include(created['token'], regenerated)
    end
  end
end
