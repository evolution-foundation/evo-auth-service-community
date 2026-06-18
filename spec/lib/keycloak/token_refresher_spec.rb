# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Keycloak::TokenRefresher do
  let(:issuer)          { 'https://keycloak.example.com/realms/test' }
  let(:client_id)       { 'test-client' }
  let(:refresh_token)   { 'kc-refresh-token-abc' }
  let(:token_endpoint)  { "#{issuer}/protocol/openid-connect/token" }

  let(:success_body) do
    {
      access_token:       'new-kc-access-token',
      id_token:           'new-kc-id-token',
      refresh_token:      'new-kc-refresh-token',
      expires_in:         300,
      refresh_expires_in: 1800
    }.to_json
  end

  before do
    stub_const('ENV', ENV.to_h.merge(
      'KEYCLOAK_ISSUER'       => issuer,
      'KEYCLOAK_INTERNAL_URL' => issuer,
      'KEYCLOAK_CLIENT_ID'    => client_id,
      'KEYCLOAK_SSL_VERIFY'   => 'false'
    ))
  end

  describe '.refresh' do
    context 'con refresh_token válido' do
      before do
        stub_request(:post, token_endpoint)
          .with(body: hash_including('grant_type' => 'refresh_token', 'refresh_token' => refresh_token))
          .to_return(status: 200, body: success_body, headers: { 'Content-Type' => 'application/json' })
      end

      it 'retorna los nuevos tokens' do
        result = described_class.refresh(refresh_token: refresh_token)

        expect(result[:access_token]).to eq('new-kc-access-token')
        expect(result[:id_token]).to eq('new-kc-id-token')
        expect(result[:refresh_token]).to eq('new-kc-refresh-token')
        expect(result[:expires_in]).to eq(300)
        expect(result[:refresh_expires_in]).to eq(1800)
      end
    end

    context 'cuando el refresh_token está expirado (invalid_grant)' do
      before do
        stub_request(:post, token_endpoint)
          .to_return(
            status: 400,
            body: { error: 'invalid_grant', error_description: 'Token is not active' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'lanza TokenRefresher::ExpiredError' do
        expect { described_class.refresh(refresh_token: refresh_token) }
          .to raise_error(Keycloak::TokenRefresher::ExpiredError, /expired or invalid/)
      end
    end

    context 'cuando Keycloak devuelve otro error HTTP' do
      before do
        stub_request(:post, token_endpoint)
          .to_return(
            status: 500,
            body: { error: 'server_error' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'lanza TokenRefresher::Error genérico' do
        expect { described_class.refresh(refresh_token: refresh_token) }
          .to raise_error(Keycloak::TokenRefresher::Error, /HTTP 500/)
      end
    end

    context 'cuando refresh_token está en blanco' do
      it 'lanza Error sin hacer request HTTP' do
        expect { described_class.refresh(refresh_token: '') }
          .to raise_error(Keycloak::TokenRefresher::Error, /required/)
        expect(WebMock).not_to have_requested(:post, token_endpoint)
      end
    end

    context 'cuando Keycloak no es alcanzable' do
      before do
        stub_request(:post, token_endpoint).to_raise(Net::OpenTimeout)
      end

      it 'lanza TokenRefresher::Error de conectividad' do
        expect { described_class.refresh(refresh_token: refresh_token) }
          .to raise_error(Keycloak::TokenRefresher::Error, /Could not reach Keycloak/)
      end
    end
  end
end
