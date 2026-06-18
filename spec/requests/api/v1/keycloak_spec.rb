# frozen_string_literal: true

require 'rails_helper'

# Helpers comunes para los specs de Keycloak
module KeycloakSpecHelpers
  def stub_licensing
    allow(Licensing::Runtime).to receive(:context).and_return(
      instance_double(Licensing::RuntimeContext, active?: true, track_message: nil)
    )
    allow(RuntimeConfig).to receive(:account).and_return(nil)
    store_double = instance_double(Licensing::Store,
                                   load_or_create_instance_id: nil,
                                   load_runtime_data: nil)
    allow(Licensing::Store).to receive(:new).and_return(store_double)
  end

  def stub_jwt_validator_success(claims)
    allow(Keycloak::JwtValidator).to receive(:verify).and_return(claims)
  end

  def stub_jwt_validator_error(message = 'Invalid token')
    allow(Keycloak::JwtValidator).to receive(:verify)
      .and_raise(Keycloak::JwtValidator::Error, message)
  end

  def stub_code_exchanger_success(tokens = {})
    defaults = {
      access_token:       'kc-access-token',
      id_token:           'kc-id-token',
      refresh_token:      'kc-refresh-token',
      expires_in:         300,
      refresh_expires_in: 1800
    }
    allow(Keycloak::CodeExchanger).to receive(:exchange).and_return(defaults.merge(tokens))
  end

  def stub_code_exchanger_error(message = 'Exchange failed')
    allow(Keycloak::CodeExchanger).to receive(:exchange)
      .and_raise(Keycloak::CodeExchanger::Error, message)
  end

  def stub_token_refresher_success(tokens = {})
    defaults = {
      access_token:       'new-kc-access-token',
      id_token:           'new-kc-id-token',
      refresh_token:      'new-kc-refresh-token',
      expires_in:         300,
      refresh_expires_in: 1800
    }
    allow(Keycloak::TokenRefresher).to receive(:refresh).and_return(defaults.merge(tokens))
  end

  def stub_token_refresher_expired
    allow(Keycloak::TokenRefresher).to receive(:refresh)
      .and_raise(Keycloak::TokenRefresher::ExpiredError, 'Refresh token expired')
  end

  def valid_claims(email: nil)
    email ||= "kc-#{SecureRandom.hex(4)}@example.com"
    {
      'sub'   => "sub-#{SecureRandom.hex(8)}",
      'email' => email,
      'name'  => 'Keycloak User',
      'iss'   => 'https://keycloak.example.com/realms/test',
      'exp'   => 1.hour.from_now.to_i,
      'iat'   => Time.now.to_i,
      'realm_access' => { 'roles' => [] }
    }
  end
end

RSpec.describe 'POST /api/v1/auth/keycloak_exchange', type: :request do
  include KeycloakSpecHelpers

  let(:headers) { { 'Host' => 'localhost' } }

  before { stub_licensing }

  context 'cuando KEYCLOAK_ENABLED no está activo' do
    before { stub_const('ENV', ENV.to_h.merge('KEYCLOAK_ENABLED' => 'false')) }

    it 'retorna 501 Not Implemented' do
      post '/api/v1/auth/keycloak_exchange', params: { code: 'abc' }, headers: headers
      expect(response).to have_http_status(:not_implemented)
    end
  end

  context 'con KEYCLOAK_ENABLED=true' do
    before { stub_const('ENV', ENV.to_h.merge('KEYCLOAK_ENABLED' => 'true')) }

    context 'flujo PKCE (code + code_verifier)' do
      let(:claims) { valid_claims }

      before do
        stub_code_exchanger_success
        stub_jwt_validator_success(claims)
      end

      it 'retorna 200 con access_token' do
        post '/api/v1/auth/keycloak_exchange',
             params: { code: 'auth-code', code_verifier: 'pkce-verifier', redirect_uri: 'http://localhost:5173/callback' },
             headers: headers

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body.dig('data', 'token', 'access_token')).to be_present
      end

      it 'retorna los datos del usuario provisionado' do
        post '/api/v1/auth/keycloak_exchange',
             params: { code: 'auth-code', code_verifier: 'pkce-verifier', redirect_uri: 'http://localhost:5173/callback' },
             headers: headers

        body = JSON.parse(response.body)
        expect(body.dig('data', 'user', 'email')).to eq(claims['email'])
      end

      it 'guarda el keycloak_refresh_token en el usuario' do
        post '/api/v1/auth/keycloak_exchange',
             params: { code: 'auth-code', code_verifier: 'pkce-verifier', redirect_uri: 'http://localhost:5173/callback' },
             headers: headers

        user = User.find_by(email: claims['email'])
        expect(user.keycloak_refresh_token).to eq('kc-refresh-token')
      end
    end

    context 'flujo sin PKCE (solo code, sin code_verifier)' do
      let(:claims) { valid_claims }

      before do
        stub_code_exchanger_success
        stub_jwt_validator_success(claims)
      end

      it 'retorna 200 (PKCE es opcional)' do
        post '/api/v1/auth/keycloak_exchange',
             params: { code: 'auth-code', redirect_uri: 'http://localhost:5173/callback' },
             headers: headers

        expect(response).to have_http_status(:ok)
      end
    end

    context 'flujo de token directo (keycloak_token)' do
      let(:claims) { valid_claims }

      before { stub_jwt_validator_success(claims) }

      it 'retorna 200 con access_token' do
        post '/api/v1/auth/keycloak_exchange',
             params: { keycloak_token: 'raw-kc-jwt' },
             headers: headers

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body.dig('data', 'token', 'access_token')).to be_present
      end
    end

    context 'sin code ni keycloak_token' do
      it 'retorna 400 Bad Request' do
        post '/api/v1/auth/keycloak_exchange', params: {}, headers: headers
        expect(response).to have_http_status(:bad_request)
      end
    end

    context 'cuando el intercambio de código falla' do
      before { stub_code_exchanger_error('HTTP 502: upstream error') }

      it 'retorna 502 Bad Gateway' do
        post '/api/v1/auth/keycloak_exchange',
             params: { code: 'bad-code', redirect_uri: 'http://localhost:5173/callback' },
             headers: headers

        expect(response).to have_http_status(:bad_gateway)
        body = JSON.parse(response.body)
        expect(body.dig('error', 'code')).to eq('TOKEN_EXCHANGE_FAILED')
      end
    end

    context 'cuando el JWT es inválido' do
      before do
        stub_code_exchanger_success
        stub_jwt_validator_error('Invalid issuer')
      end

      it 'retorna 401 Unauthorized' do
        post '/api/v1/auth/keycloak_exchange',
             params: { code: 'auth-code', redirect_uri: 'http://localhost:5173/callback' },
             headers: headers

        expect(response).to have_http_status(:unauthorized)
        body = JSON.parse(response.body)
        expect(body.dig('error', 'code')).to eq('INVALID_TOKEN')
      end
    end

    context 'cuando el JWT está expirado' do
      before do
        stub_code_exchanger_success
        stub_jwt_validator_error('Token has expired')
      end

      it 'retorna 401 Unauthorized con mensaje de expiración' do
        post '/api/v1/auth/keycloak_exchange',
             params: { code: 'auth-code', redirect_uri: 'http://localhost:5173/callback' },
             headers: headers

        expect(response).to have_http_status(:unauthorized)
        body = JSON.parse(response.body)
        expect(body.dig('error', 'message')).to match(/expired/i)
      end
    end
  end
end

RSpec.describe 'POST /api/v1/auth/keycloak_refresh', type: :request do
  include KeycloakSpecHelpers

  let(:headers) { { 'Host' => 'localhost' } }

  before { stub_licensing }

  context 'cuando KEYCLOAK_ENABLED no está activo' do
    before { stub_const('ENV', ENV.to_h.merge('KEYCLOAK_ENABLED' => 'false')) }

    it 'retorna 501 Not Implemented' do
      post '/api/v1/auth/keycloak_refresh', params: { keycloak_refresh_token: 'rt' }, headers: headers
      expect(response).to have_http_status(:not_implemented)
    end
  end

  context 'con KEYCLOAK_ENABLED=true' do
    before { stub_const('ENV', ENV.to_h.merge('KEYCLOAK_ENABLED' => 'true')) }

    context 'con refresh_token válido' do
      let(:claims) { valid_claims }

      before do
        stub_token_refresher_success
        stub_jwt_validator_success(claims)
      end

      it 'retorna 200 con nuevo access_token' do
        post '/api/v1/auth/keycloak_refresh',
             params: { keycloak_refresh_token: 'valid-rt' },
             headers: headers

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body.dig('data', 'token', 'access_token')).to be_present
      end

      it 'actualiza el keycloak_refresh_token del usuario' do
        post '/api/v1/auth/keycloak_refresh',
             params: { keycloak_refresh_token: 'valid-rt' },
             headers: headers

        user = User.find_by(email: claims['email'])
        expect(user.keycloak_refresh_token).to eq('new-kc-refresh-token')
      end
    end

    context 'sin refresh_token' do
      before { stub_const('ENV', ENV.to_h.merge('KEYCLOAK_ENABLED' => 'true')) }

      it 'retorna 400 Bad Request' do
        post '/api/v1/auth/keycloak_refresh', params: {}, headers: headers
        expect(response).to have_http_status(:bad_request)
      end
    end

    context 'cuando el refresh_token está expirado' do
      before { stub_token_refresher_expired }

      it 'retorna 401 Unauthorized con error REFRESH_TOKEN_EXPIRED' do
        post '/api/v1/auth/keycloak_refresh',
             params: { keycloak_refresh_token: 'expired-rt' },
             headers: headers

        expect(response).to have_http_status(:unauthorized)
        body = JSON.parse(response.body)
        expect(body.dig('error', 'code')).to eq('REFRESH_TOKEN_EXPIRED')
      end
    end

    context 'cuando el nuevo access_token de Keycloak es inválido' do
      before do
        stub_token_refresher_success
        stub_jwt_validator_error('Invalid issuer after refresh')
      end

      it 'retorna 401 Unauthorized' do
        post '/api/v1/auth/keycloak_refresh',
             params: { keycloak_refresh_token: 'valid-rt' },
             headers: headers

        expect(response).to have_http_status(:unauthorized)
        body = JSON.parse(response.body)
        expect(body.dig('error', 'code')).to eq('INVALID_TOKEN')
      end
    end
  end
end
