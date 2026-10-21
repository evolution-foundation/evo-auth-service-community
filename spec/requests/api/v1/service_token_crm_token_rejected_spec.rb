# frozen_string_literal: true

require 'rails_helper'

# CRM-829: the CRM's own token used to double as this service's credential
# whenever EVOAI_AUTH_API_TOKEN was blank, so the public quickstart value
# authenticated as a service and read the whole user directory.
RSpec.describe 'Service token: EVOAI_CRM_API_TOKEN is not a credential', type: :request do
  let(:crm_token) { 'crm-token-probe' }
  let(:auth_token) { 'auth-token-probe' }

  before do
    User.create!(name: 'Directory Entry', email: "entry-#{SecureRandom.hex(3)}@example.com",
                 password: 'Test123!@', password_confirmation: 'Test123!@', confirmed_at: Time.current)
  end

  def with_env(values)
    originals = values.keys.index_with { |key| ENV.fetch(key, nil) }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    originals.each { |key, value| ENV[key] = value }
  end

  def list_users_with(header, token)
    get '/api/v1/users', headers: { header => token, 'Host' => 'localhost' }
  end

  def error_code
    JSON.parse(response.body)['code']
  end

  context 'when only EVOAI_CRM_API_TOKEN is set' do
    around do |example|
      with_env('EVOAI_CRM_API_TOKEN' => crm_token, 'EVOAI_AUTH_API_TOKEN' => nil) { example.run }
    end

    it 'rejects the CRM token in X-Service-Token' do
      list_users_with('X-Service-Token', crm_token)

      expect(response).to have_http_status(:unauthorized)
      expect(error_code).to eq('SERVICE_TOKEN_UNAUTHORIZED')
    end

    it 'rejects the CRM token in X-Internal-API-Token' do
      list_users_with('X-Internal-API-Token', crm_token)

      expect(response).to have_http_status(:unauthorized)
      expect(error_code).to eq('SERVICE_TOKEN_UNAUTHORIZED')
    end
  end

  context 'when both tokens are set' do
    around do |example|
      with_env('EVOAI_CRM_API_TOKEN' => crm_token, 'EVOAI_AUTH_API_TOKEN' => auth_token) { example.run }
    end

    it 'rejects the CRM token' do
      list_users_with('X-Service-Token', crm_token)

      expect(response).to have_http_status(:unauthorized)
      expect(error_code).to eq('SERVICE_TOKEN_UNAUTHORIZED')
    end

    it 'accepts EVOAI_AUTH_API_TOKEN' do
      list_users_with('X-Service-Token', auth_token)

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'ServiceTokenAuthConcern.verify_configured!' do
    it 'refuses to boot without EVOAI_AUTH_API_TOKEN, even with the CRM token set' do
      with_env('EVOAI_CRM_API_TOKEN' => crm_token, 'EVOAI_AUTH_API_TOKEN' => nil) do
        expect { ServiceTokenAuthConcern.verify_configured! }.to raise_error(/EVOAI_AUTH_API_TOKEN must be set/)
      end
    end

    it 'refuses a blank EVOAI_AUTH_API_TOKEN' do
      with_env('EVOAI_AUTH_API_TOKEN' => '  ') do
        expect { ServiceTokenAuthConcern.verify_configured! }.to raise_error(/EVOAI_AUTH_API_TOKEN must be set/)
      end
    end

    it 'refuses the public quickstart default' do
      with_env('EVOAI_AUTH_API_TOKEN' => '6e10e689-58ce-4416-bf0d-f5818bf2dcf8') do
        expect { ServiceTokenAuthConcern.verify_configured! }.to raise_error(/public quickstart default/)
      end
    end

    it 'boots when EVOAI_AUTH_API_TOKEN is set' do
      with_env('EVOAI_AUTH_API_TOKEN' => auth_token) do
        expect { ServiceTokenAuthConcern.verify_configured! }.not_to raise_error
      end
    end
  end
end
