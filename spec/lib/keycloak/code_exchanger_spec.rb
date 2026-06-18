# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Keycloak::CodeExchanger do
  let(:issuer)     { 'https://keycloak.example.com/realms/test' }
  let(:client_id)  { 'test-client' }
  let(:code)       { 'auth-code-xyz' }
  let(:verifier)   { 'pkce-verifier-abc' }
  let(:redirect)   { 'http://localhost:5173/auth/callback' }

  let(:token_endpoint) { "#{issuer}/protocol/openid-connect/token" }

  let(:success_response_body) do
    {
      access_token:       'kc-access-token',
      id_token:           'kc-id-token',
      refresh_token:      'kc-refresh-token',
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

  describe '.exchange' do
    context 'con PKCE (code_verifier presente)' do
      before do
        stub_request(:post, token_endpoint)
          .with(body: hash_including('code_verifier' => verifier, 'grant_type' => 'authorization_code'))
          .to_return(status: 200, body: success_response_body, headers: { 'Content-Type' => 'application/json' })
      end

      it 'retorna access_token, id_token y refresh_token' do
        result = described_class.exchange(code: code, code_verifier: verifier, redirect_uri: redirect)

        expect(result[:access_token]).to eq('kc-access-token')
        expect(result[:id_token]).to eq('kc-id-token')
        expect(result[:refresh_token]).to eq('kc-refresh-token')
        expect(result[:expires_in]).to eq(300)
        expect(result[:refresh_expires_in]).to eq(1800)
      end

      it 'no emite advertencia de PKCE' do
        expect(Rails.logger).not_to receive(:warn)
        described_class.exchange(code: code, code_verifier: verifier, redirect_uri: redirect)
      end
    end

    context 'sin PKCE (code_verifier ausente)' do
      before do
        stub_request(:post, token_endpoint)
          .with { |req| !req.body.include?('code_verifier') }
          .to_return(status: 200, body: success_response_body, headers: { 'Content-Type' => 'application/json' })
      end

      it 'completa el intercambio igual' do
        result = described_class.exchange(code: code, redirect_uri: redirect)
        expect(result[:access_token]).to eq('kc-access-token')
      end

      it 'emite advertencia de seguridad sobre PKCE' do
        expect(Rails.logger).to receive(:warn).with(/PKCE code_verifier not provided/)
        described_class.exchange(code: code, redirect_uri: redirect)
      end

      it 'no incluye code_verifier en el body del request' do
        described_class.exchange(code: code, redirect_uri: redirect)
        expect(WebMock).to have_requested(:post, token_endpoint)
          .with { |req| !req.body.include?('code_verifier') }
      end
    end

    context 'cuando Keycloak devuelve error HTTP' do
      before do
        stub_request(:post, token_endpoint)
          .to_return(status: 400, body: { error: 'invalid_grant', error_description: 'Code expired' }.to_json,
                     headers: { 'Content-Type' => 'application/json' })
      end

      it 'lanza CodeExchanger::Error con el código HTTP' do
        expect { described_class.exchange(code: code, redirect_uri: redirect) }
          .to raise_error(Keycloak::CodeExchanger::Error, /HTTP 400/)
      end
    end

    context 'cuando la respuesta no contiene access_token' do
      before do
        stub_request(:post, token_endpoint)
          .to_return(status: 200, body: { id_token: 'only-this' }.to_json,
                     headers: { 'Content-Type' => 'application/json' })
      end

      it 'lanza CodeExchanger::Error' do
        expect { described_class.exchange(code: code, redirect_uri: redirect) }
          .to raise_error(Keycloak::CodeExchanger::Error, /missing access_token/)
      end
    end

    context 'cuando Keycloak no es alcanzable' do
      before do
        stub_request(:post, token_endpoint).to_raise(Errno::ECONNREFUSED)
      end

      it 'lanza CodeExchanger::Error con mensaje de conectividad' do
        expect { described_class.exchange(code: code, redirect_uri: redirect) }
          .to raise_error(Keycloak::CodeExchanger::Error, /Could not reach Keycloak/)
      end
    end

    context 'cuando KEYCLOAK_ISSUER no está configurado' do
      before do
        stub_const('ENV', ENV.to_h.reject { |k, _| %w[KEYCLOAK_ISSUER KEYCLOAK_INTERNAL_URL].include?(k) })
      end

      it 'lanza CodeExchanger::Error de configuración' do
        expect { described_class.exchange(code: code, redirect_uri: redirect) }
          .to raise_error(Keycloak::CodeExchanger::Error, /KEYCLOAK_ISSUER is not configured/)
      end
    end
  end
end
