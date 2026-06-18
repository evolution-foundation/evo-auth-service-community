# frozen_string_literal: true

require 'rails_helper'
require 'openssl'
require 'jwt'

RSpec.describe Keycloak::JwtValidator do
  let(:rsa_key)    { OpenSSL::PKey::RSA.generate(2048) }
  let(:public_key) { rsa_key.public_key }
  let(:issuer)     { 'https://keycloak.example.com/realms/test' }
  let(:client_id)  { 'test-client' }

  let(:kid) { 'test-kid-001' }

  let(:valid_claims) do
    {
      'sub'               => 'user-sub-123',
      'iss'               => issuer,
      'email'             => 'user@example.com',
      'preferred_username'=> 'testuser',
      'exp'               => 1.hour.from_now.to_i,
      'nbf'               => 1.minute.ago.to_i,
      'iat'               => Time.now.to_i
    }
  end

  def encode_token(claims, key: rsa_key, algorithm: 'RS256')
    JWT.encode(claims, key, algorithm, { kid: kid })
  end

  let(:jwks_uri) { "#{issuer}/protocol/openid-connect/certs" }

  let(:jwks_response) do
    jwk = JWT::JWK.new(rsa_key, kid: kid)
    { keys: [jwk.export] }.to_json
  end

  before do
    stub_const('ENV', ENV.to_h.merge(
      'KEYCLOAK_ISSUER'       => issuer,
      'KEYCLOAK_INTERNAL_URL' => issuer,
      'KEYCLOAK_SSL_VERIFY'   => 'false'
    ))

    # Resetear cache del validador entre tests
    described_class.instance_variable_set(:@jwks, nil)
    described_class.instance_variable_set(:@fetched_at, nil)

    # Stubear el endpoint JWKS con WebMock
    stub_request(:get, jwks_uri)
      .to_return(status: 200, body: jwks_response, headers: { 'Content-Type' => 'application/json' })
  end

  describe '.verify' do
    context 'con un token válido RS256' do
      it 'retorna los claims correctos' do
        token  = encode_token(valid_claims)
        result = described_class.verify(token)

        expect(result['sub']).to eq('user-sub-123')
        expect(result['email']).to eq('user@example.com')
        expect(result['iss']).to eq(issuer)
      end
    end

    context 'con un token válido RS384' do
      it 'retorna los claims correctos' do
        token  = encode_token(valid_claims, algorithm: 'RS384')
        result = described_class.verify(token)

        expect(result['sub']).to eq('user-sub-123')
      end
    end

    context 'con un token válido RS512' do
      it 'retorna los claims correctos' do
        token  = encode_token(valid_claims, algorithm: 'RS512')
        result = described_class.verify(token)

        expect(result['sub']).to eq('user-sub-123')
      end
    end

    context 'con issuer inválido' do
      it 'lanza Error con mensaje descriptivo' do
        bad_claims = valid_claims.merge('iss' => 'https://evil.example.com/realms/hack')
        token = encode_token(bad_claims)

        expect { described_class.verify(token) }
          .to raise_error(Keycloak::JwtValidator::Error, /Invalid issuer/)
      end
    end

    context 'cuando el issuer interno (KEYCLOAK_INTERNAL_URL) difiere del público' do
      let(:internal_url) { 'http://keycloak:8080/realms/test' }

      before do
        stub_const('ENV', ENV.to_h.merge(
          'KEYCLOAK_ISSUER'       => issuer,
          'KEYCLOAK_INTERNAL_URL' => internal_url,
          'KEYCLOAK_SSL_VERIFY'   => 'false'
        ))
        described_class.instance_variable_set(:@jwks, nil)
        described_class.instance_variable_set(:@fetched_at, nil)
        internal_jwks_uri = "#{internal_url}/protocol/openid-connect/certs"
        stub_request(:get, internal_jwks_uri)
          .to_return(status: 200, body: jwks_response, headers: { 'Content-Type' => 'application/json' })
      end

      it 'acepta el issuer interno como válido' do
        token_with_internal_iss = encode_token(valid_claims.merge('iss' => internal_url))
        expect { described_class.verify(token_with_internal_iss) }.not_to raise_error
      end
    end

    context 'con token expirado' do
      it 'lanza Error con mensaje que indica expiración' do
        expired_claims = valid_claims.merge('exp' => 1.hour.ago.to_i)
        token = encode_token(expired_claims)

        expect { described_class.verify(token) }
          .to raise_error(Keycloak::JwtValidator::Error, /expired/)
      end
    end

    context 'sin claim exp' do
      it 'lanza Error indicando que falta el claim exp' do
        claims_without_exp = valid_claims.reject { |k, _| k == 'exp' }
        token = encode_token(claims_without_exp)

        expect { described_class.verify(token) }
          .to raise_error(Keycloak::JwtValidator::Error, /missing the 'exp' claim/)
      end
    end

    context 'con claim nbf en el futuro' do
      it 'lanza Error (la gem jwt o nuestro código lo rechaza)' do
        future_nbf_claims = valid_claims.merge('nbf' => 10.minutes.from_now.to_i)
        token = encode_token(future_nbf_claims)

        expect { described_class.verify(token) }
          .to raise_error(Keycloak::JwtValidator::Error)
      end
    end

    context 'con firma inválida' do
      it 'lanza Error' do
        other_key = OpenSSL::PKey::RSA.generate(2048)
        token = encode_token(valid_claims, key: other_key)

        expect { described_class.verify(token) }
          .to raise_error(Keycloak::JwtValidator::Error)
      end
    end

    context 'con token malformado' do
      it 'lanza Error' do
        expect { described_class.verify('not.a.jwt') }
          .to raise_error(Keycloak::JwtValidator::Error)
      end
    end

    context 'cuando KEYCLOAK_ISSUER no está configurado' do
      before do
        stub_const('ENV', ENV.to_h.reject { |k, _| %w[KEYCLOAK_ISSUER KEYCLOAK_INTERNAL_URL].include?(k) })
        described_class.instance_variable_set(:@jwks, nil)
        described_class.instance_variable_set(:@fetched_at, nil)
        # Sin KEYCLOAK_ISSUER, load_jwks falla al construir la URL
        # El error se propaga como Keycloak::JwtValidator::Error
        stub_request(:get, /openid-connect\/certs/).to_raise(StandardError.new('no issuer'))
      end

      it 'lanza Error (sin clave disponible o sin issuer configurado)' do
        token = encode_token(valid_claims)
        # Sin KEYCLOAK_ISSUER, load_jwks falla silenciosamente y no hay
        # clave disponible para decodificar → Error de verificación
        expect { described_class.verify(token) }
          .to raise_error(Keycloak::JwtValidator::Error)
      end
    end
  end
end
