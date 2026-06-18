# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Keycloak::UserProvisioner do
  let(:sub)   { 'keycloak-sub-abc123' }
  let(:email) { "kc-#{SecureRandom.hex(4)}@example.com" }

  let(:base_claims) do
    {
      'sub'                => sub,
      'email'              => email,
      'name'               => 'Test User',
      'preferred_username' => 'testuser'
    }
  end

  before do
    stub_const('ENV', ENV.to_h.merge(
      'KEYCLOAK_CLIENT_ID'    => 'test-client',
      'KEYCLOAK_ROLES_CLAIM'  => 'realm_access.roles'
    ))
  end

  describe '.provision!' do
    context 'usuario nuevo (no existe en DB)' do
      it 'crea el usuario con provider=keycloak' do
        user = described_class.provision!(base_claims)

        expect(user).to be_persisted
        expect(user.email).to eq(email)
        expect(user.provider).to eq('keycloak')
        expect(user.keycloak_sub).to eq(sub)
      end

      it 'usa el name del claim como nombre de display' do
        user = described_class.provision!(base_claims)
        expect(user.name).to eq('Test User')
      end

      it 'usa preferred_username cuando no hay name' do
        user = described_class.provision!(base_claims.except('name'))
        expect(user.name).to eq('testuser')
      end
    end

    context 'usuario existente por keycloak_sub' do
      let!(:existing_user) do
        User.create!(
          name: 'Existing User', email: email,
          password: 'Pass123!', password_confirmation: 'Pass123!',
          confirmed_at: Time.current, keycloak_sub: sub
        )
      end

      it 'retorna el usuario existente sin duplicar' do
        expect { described_class.provision!(base_claims) }.not_to change(User, :count)
        user = described_class.provision!(base_claims)
        expect(user.id).to eq(existing_user.id)
      end

      it 'actualiza el email si cambió en Keycloak' do
        new_email = "new-#{SecureRandom.hex(4)}@example.com"
        user = described_class.provision!(base_claims.merge('email' => new_email))
        expect(user.reload.email).to eq(new_email)
      end
    end

    context 'usuario existente por email (sin keycloak_sub previo)' do
      let!(:existing_user) do
        User.create!(
          name: 'Email User', email: email,
          password: 'Pass123!', password_confirmation: 'Pass123!',
          confirmed_at: Time.current
        )
      end

      it 'vincula el keycloak_sub al usuario existente' do
        described_class.provision!(base_claims)
        expect(existing_user.reload.keycloak_sub).to eq(sub)
      end

      it 'no cambia el provider del usuario existente' do
        described_class.provision!(base_claims)
        expect(existing_user.reload.provider).to eq('email')
      end
    end

    context 'sincronización de roles' do
      let!(:agent_role) { Role.find_or_create_by!(key: 'agent') { |r| r.name = 'Agent' } }
      let!(:admin_role) { Role.find_or_create_by!(key: 'admin') { |r| r.name = 'Admin' } }

      let(:claims_with_roles) do
        base_claims.merge(
          'realm_access' => { 'roles' => ['admin'] }
        )
      end

      it 'asigna el rol correspondiente al claim de Keycloak' do
        user = described_class.provision!(claims_with_roles)
        expect(user.reload.roles.map(&:key)).to include('admin')
      end

      it 'asigna el rol agent por defecto cuando no hay roles en el claim' do
        user = described_class.provision!(base_claims)
        expect(user.reload.roles.map(&:key)).to include('agent')
      end

      it 'revoca roles que Keycloak ya no otorga' do
        user = described_class.provision!(claims_with_roles)
        expect(user.reload.roles.map(&:key)).not_to include('agent')
      end

      it 'asigna roles nuevos en logins posteriores que no existían en login anterior' do
        user = described_class.provision!(base_claims)
        expect(user.reload.roles.map(&:key)).to include('agent')

        new_claims = base_claims.merge(
          'realm_access' => { 'roles' => ['admin'] }
        )
        user = described_class.provision!(new_claims)

        expect(user.reload.roles.map(&:key)).to include('admin')
        expect(user.reload.roles.map(&:key)).not_to include('agent')
      end
    end

    context 'cuando falta el claim email' do
      it 'lanza un error de validación' do
        expect { described_class.provision!(base_claims.except('email')) }
          .to raise_error(StandardError)
      end
    end
  end
end
