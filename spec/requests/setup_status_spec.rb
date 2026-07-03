# frozen_string_literal: true

require 'rails_helper'

# Regression spec for EVO-971. The setup wizard must be shown whenever
# there is no admin user, even if licensing somehow reports active — a DB
# wipe, partial bootstrap, or restore from a stale snapshot left installs
# stranded on /login with no way to create the first super-admin.
RSpec.describe 'GET /setup/status', type: :request do
  # `track_message` is stubbed because the SetupGate Rack middleware calls it on
  # every request when the context is active (observability, non-blocking).
  let(:active_ctx)   { instance_double(Licensing::RuntimeContext, active?: true,  instance_id: 'inst-abc', api_key: 'abcd1234efgh5678ijkl', track_message: nil) }
  let(:inactive_ctx) { instance_double(Licensing::RuntimeContext, active?: false, instance_id: 'inst-abc') }

  context 'when licensing is active but no admin user exists' do
    before do
      allow(Licensing::Runtime).to receive(:context).and_return(active_ctx)
      allow(User).to receive(:exists?).and_return(false)
    end

    it "reports 'inactive' so the frontend shows the setup wizard" do
      get '/setup/status'

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['status']).to eq('inactive')
      # api_key is surfaced whenever the license is active (masked), independent
      # of bootstrap state — the wizard can show it while still routing to /setup.
      expect(body['api_key']).to eq('abcd1234...ijkl')
    end
  end

  context 'when licensing is active and an admin user exists' do
    before do
      allow(Licensing::Runtime).to receive(:context).and_return(active_ctx)
      allow(User).to receive(:exists?).and_return(true)
    end

    it "reports 'active' with a masked api_key" do
      get '/setup/status'

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['status']).to eq('active')
      expect(body['api_key']).to eq('abcd1234...ijkl')
    end
  end

  context 'when licensing is inactive but an admin user exists' do
    before do
      allow(Licensing::Runtime).to receive(:context).and_return(inactive_ctx)
      allow(User).to receive(:exists?).and_return(true)
    end

    # Post EVO-971 `status` is derived from bootstrap state, not the licensing
    # handshake — a licensing outage must never trap a bootstrapped install on
    # /setup. The license state is surfaced separately via `licensed`.
    it "reports 'active' (bootstrapped) with licensed: false" do
      get '/setup/status'

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['status']).to eq('active')
      expect(body['licensed']).to be(false)
    end
  end

  context 'when licensing runtime has not been initialized' do
    before { allow(Licensing::Runtime).to receive(:context).and_return(nil) }

    it "reports 'inactive' with a nil instance_id" do
      get '/setup/status'

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to eq('status' => 'inactive', 'instance_id' => nil, 'extra_setup_steps' => false)
    end
  end

  # The `extra_setup_steps` flag gates the Setup wizard's extra steps: it is only
  # shown when a registered consumer contributes steps after the account step.
  # Backed by the :extra_setup_steps extension point; community default is false.
  context 'the extra_setup_steps capability flag' do
    before do
      allow(Licensing::Runtime).to receive(:context).and_return(active_ctx)
      allow(User).to receive(:exists?).and_return(false)
    end

    after do
      # The registry is process-global — never let an override leak between examples.
      EvoExtensionPoints.reset(:extra_setup_steps)
    end

    it 'is false on a community-only install (no consumer) and carries no whitelabel key' do
      get '/setup/status'

      body = JSON.parse(response.body)
      expect(body['extra_setup_steps']).to be(false)
      expect(body).not_to have_key('whitelabel')
    end

    it 'is true when a consumer registers the :extra_setup_steps override' do
      EvoExtensionPoints.replace(:extra_setup_steps) { true }

      get '/setup/status'

      expect(JSON.parse(response.body)['extra_setup_steps']).to be(true)
    end
  end
end
