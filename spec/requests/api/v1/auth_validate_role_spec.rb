# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'POST /api/v1/auth/validate — the role it presents', type: :request do
  let(:password) { 'Valid1!Pass' }

  let(:user) do
    User.create!(
      name: 'Validate User',
      email: "validate-#{SecureRandom.hex(4)}@example.com",
      password: password,
      password_confirmation: password,
      confirmed_at: Time.current
    )
  end

  let(:token) { AccessToken.create!(owner: user, name: 'validate-token', scopes: 'default') }
  let(:headers) { { 'api_access_token' => token.token, 'Host' => 'localhost' } }

  def assign(user, key, at:)
    role = Role.find_by(key: key) || Role.create!(key: key, name: key.titleize, type: 'account', system: false)
    UserRole.assign_role_to_user(user, role)
    UserRole.where(user: user, role: role).update_all(created_at: at)
    role
  end

  def assign_derived(user, at:, scope: 'global')
    assign(user, "evo_derived_#{user.id}_#{scope}", at: at)
  end

  def validate!
    post '/api/v1/auth/validate', headers: headers
    expect(response).to have_http_status(:ok)
    JSON.parse(response.body)['data']
  end

  it 'presents the real role and not the derived one' do
    assign_derived(user, at: 2.days.ago)
    assign(user, 'super_admin', at: 1.day.ago)

    expect(validate!.dig('user', 'role', 'key')).to eq('super_admin')
  end

  it 'presents the real role when the derived one is the newer row' do
    assign(user, 'evolution_admin', at: 2.days.ago)
    assign_derived(user, at: 1.day.ago)

    expect(validate!.dig('user', 'role', 'key')).to eq('evolution_admin')
  end

  # A promotion used to leave the previous grant behind (CRM-496): presenting
  # the older row put an admin back at the authority level they were raised from.
  it 'presents the role of the last promotion, not the one it replaced' do
    assign(user, 'agent', at: 2.days.ago)
    assign(user, 'super_admin', at: 1.day.ago)

    expect(validate!.dig('user', 'role', 'key')).to eq('super_admin')
  end

  it 'presents the derived role when the user holds nothing else' do
    derived = assign_derived(user, at: 1.day.ago)

    expect(validate!.dig('user', 'role', 'key')).to eq(derived.key)
  end

  it 'echoes the same role into accounts' do
    allow(RuntimeConfig).to receive(:account).and_return({ 'id' => 1, 'name' => 'Acme' })
    assign_derived(user, at: 2.days.ago)
    assign(user, 'super_admin', at: 1.day.ago)

    data = validate!

    expect(data['accounts'].first.dig('role', 'key')).to eq('super_admin')
    expect(data['accounts'].first.dig('role', 'key')).to eq(data.dig('user', 'role', 'key'))
  end
end
