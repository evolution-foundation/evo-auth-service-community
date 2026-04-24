# frozen_string_literal: true

require 'rails_helper'

# Regression spec for EVO-971. The setup wizard must be shown whenever
# there is no admin user, even if licensing somehow reports active — a DB
# wipe, partial bootstrap, or restore from a stale snapshot left installs
# stranded on /login with no way to create the first super-admin.
RSpec.describe 'GET /setup/status', type: :request do
  let(:active_ctx)   { instance_double(Licensing::RuntimeContext, active?: true,  instance_id: 'inst-abc', api_key: 'abcd1234efgh5678ijkl') }
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
      expect(body).not_to have_key('api_key')
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

  context 'when licensing is inactive' do
    before do
      allow(Licensing::Runtime).to receive(:context).and_return(inactive_ctx)
      allow(User).to receive(:exists?).and_return(true)
    end

    it "reports 'inactive' regardless of user state" do
      get '/setup/status'

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['status']).to eq('inactive')
    end
  end

  context 'when licensing runtime has not been initialized' do
    before { allow(Licensing::Runtime).to receive(:context).and_return(nil) }

    it "reports 'inactive' with a nil instance_id" do
      get '/setup/status'

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to eq('status' => 'inactive', 'instance_id' => nil)
    end
  end
end
