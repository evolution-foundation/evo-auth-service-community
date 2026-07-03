# frozen_string_literal: true

require 'rails_helper'

# POST /setup/bootstrap creates the first admin. In an enterprise deployment the
# same flow must also grant the global `evolution_admin` membership (the row the
# licensing engine's admin routes require). The auth service shares the
# evo_community DB with the enterprise gem, whose membership table only exists
# there; the auth schema does not carry enterprise tables, so we create a minimal
# stand-in for the test DB. The users.agency_id bridge is an enterprise-DB trigger
# and is covered by the gem's seed_singleton_org spec, not here.
RSpec.describe 'POST /setup/bootstrap', type: :request do
  let(:memberships) { 'evo_enterprise_tenant_memberships' }
  let(:params) do
    {
      first_name: 'Owner',
      last_name:  'Admin',
      email:      'owner@evo.local',
      password:   'ChangeMe123!',
      password_confirmation: 'ChangeMe123!'
    }
  end

  before(:all) do
    conn = ActiveRecord::Base.connection
    conn.execute(<<~SQL)
      CREATE TABLE IF NOT EXISTS evo_enterprise_tenant_memberships (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id uuid NOT NULL,
        tenant_id uuid,
        role varchar NOT NULL,
        created_at timestamptz NOT NULL DEFAULT now(),
        updated_at timestamptz NOT NULL DEFAULT now()
      )
    SQL
    conn.execute(<<~SQL)
      CREATE UNIQUE INDEX IF NOT EXISTS idx_evo_enterprise_memberships_user_global
      ON evo_enterprise_tenant_memberships (user_id) WHERE tenant_id IS NULL
    SQL
  end

  after(:all) do
    ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS evo_enterprise_tenant_memberships")
  end

  it 'creates the first admin with super_admin + the global evolution_admin membership' do
    expect(User.count).to eq(0)

    post '/setup/bootstrap', params: params

    expect(response).to have_http_status(:created)

    user = User.find_by(email: 'owner@evo.local')
    expect(user).to be_present
    expect(user.has_role?('super_admin')).to be(true)

    membership = ActiveRecord::Base.connection.select_one(<<~SQL)
      SELECT role, tenant_id FROM #{memberships} WHERE user_id = '#{user.id}'
    SQL
    expect(membership).to be_present
    expect(membership['role']).to eq('evolution_admin')
    expect(membership['tenant_id']).to be_nil
  end
end
