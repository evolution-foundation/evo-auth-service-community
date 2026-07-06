# frozen_string_literal: true

require 'rails_helper'

# POST /setup/bootstrap creates the first admin user and dispatches the neutral
# `:after_bootstrap` extension point INSIDE the bootstrap transaction, right
# after the admin user and its global role are created. The community assigns no
# meaning to the request's `extension_payload`; it forwards the opaque bag to the
# hook verbatim. A registered consumer (the enterprise overlay, out of scope
# here) is what restores the old enterprise behavior — the community knows
# nothing about it.
RSpec.describe 'POST /setup/bootstrap', type: :request do
  # SetupBootstrapService#run_seeds (load db/seeds.rb) commits, which defeats the
  # transactional-fixture rollback and leaks the created admin across examples
  # (the 2nd bootstrap then hits an already-bootstrapped state). Manage isolation
  # explicitly instead: truncate users per example.
  self.use_transactional_tests = false

  let(:base_params) do
    {
      first_name: 'Owner',
      last_name:  'Admin',
      email:      'owner@evo.local',
      password:   'ChangeMe123!',
      password_confirmation: 'ChangeMe123!'
    }
  end

  before do
    ActiveRecord::Base.connection.execute('TRUNCATE users CASCADE')
  end

  after do
    # The registry is process-global — never let an override leak between examples.
    EvoExtensionPoints.reset(:after_bootstrap)
  end

  it 'creates the first admin with super_admin and returns a survey_token' do
    expect(User.count).to eq(0)

    post '/setup/bootstrap', params: base_params

    expect(response).to have_http_status(:created)

    user = User.find_by(email: 'owner@evo.local')
    expect(user).to be_present
    expect(user.has_role?('super_admin')).to be(true)

    body = JSON.parse(response.body)
    expect(body['survey_token']).to be_present
  end

  it 'invokes the :after_bootstrap hook with the persisted user and the opaque payload' do
    received = nil
    EvoExtensionPoints.replace(:after_bootstrap) { |user:, payload:| received = [user.id, payload] }

    post '/setup/bootstrap', params: base_params.merge(extension_payload: { 'foo' => 'bar' })

    expect(response).to have_http_status(:created)
    expect(received).not_to be_nil
    expect(received.first).to eq(User.last.id)
    expect(received.last).to eq({ 'foo' => 'bar' })
  end

  it 'still succeeds with no consumer registered (community no-op default)' do
    post '/setup/bootstrap', params: base_params

    expect(response).to have_http_status(:created)
    expect(User.count).to eq(1)
  end

  # extension_payload is opaque: a malformed (non-object) value must not 500 this
  # public, unauthenticated endpoint. It degrades to {} and the hook still fires.
  it 'does not 500 when extension_payload arrives as a non-hash scalar' do
    received = :untouched
    EvoExtensionPoints.replace(:after_bootstrap) { |user:, payload:| received = payload }

    post '/setup/bootstrap',
         params: base_params.merge(extension_payload: 'not-an-object').to_json,
         headers: { 'CONTENT_TYPE' => 'application/json' }

    expect(response).to have_http_status(:created)
    expect(received).to eq({})
  end

  it 'rolls the whole install back when the :after_bootstrap consumer raises' do
    EvoExtensionPoints.replace(:after_bootstrap) { |user:, payload:| raise 'consumer exploded' }

    expect do
      post '/setup/bootstrap', params: base_params
    end.to raise_error('consumer exploded')

    # The hook runs inside the bootstrap transaction, so its exception rolls the
    # user creation back — atomic by design.
    expect(User.count).to eq(0)
  end
end
