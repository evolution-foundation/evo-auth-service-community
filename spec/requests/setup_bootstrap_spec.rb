# frozen_string_literal: true

require 'rails_helper'

# POST /setup/bootstrap creates the first admin and, in an enterprise deployment,
# also grants the global `evolution_admin` membership and persists the operator's
# box branding onto the single agency's whitelabel row. The auth service shares
# the evo_community DB with the enterprise gem, whose tables only exist there; the
# auth schema does not carry them, so we create minimal stand-ins for the test DB.
# The users.agency_id bridge is an enterprise-DB trigger, covered by the gem's
# seed_singleton_org spec, not here.
RSpec.describe 'POST /setup/bootstrap', type: :request do
  # SetupBootstrapService#run_seeds (load db/seeds.rb) commits, which defeats the
  # transactional-fixture rollback and leaks the created admin across examples
  # (the 2nd bootstrap then hits an already-bootstrapped state). Manage isolation
  # explicitly instead: truncate users + reset the enterprise stand-ins per example.
  self.use_transactional_tests = false

  let(:memberships) { 'evo_enterprise_tenant_memberships' }
  let(:whitelabel)  { 'evo_enterprise_whitelabel_configs' }
  let(:base_params) do
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
    conn.execute("CREATE TABLE IF NOT EXISTS evo_enterprise_agencies (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), created_at timestamptz NOT NULL DEFAULT now())")
    conn.execute(<<~SQL)
      CREATE TABLE IF NOT EXISTS evo_enterprise_whitelabel_configs (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        agency_id uuid NOT NULL UNIQUE,
        primary_color varchar NOT NULL,
        app_title varchar NOT NULL,
        secondary_color varchar,
        smtp_config jsonb NOT NULL DEFAULT '{}',
        email_templates jsonb NOT NULL DEFAULT '{}',
        hide_evo_branding boolean NOT NULL DEFAULT false,
        created_at timestamptz NOT NULL DEFAULT now(),
        updated_at timestamptz NOT NULL DEFAULT now()
      )
    SQL
    # The org-única baseline the install leaves: one agency + a neutral whitelabel row.
    agency_id = conn.select_value("INSERT INTO evo_enterprise_agencies DEFAULT VALUES RETURNING id")
    conn.execute("INSERT INTO evo_enterprise_whitelabel_configs (agency_id, primary_color, app_title) VALUES ('#{agency_id}', '#22C55E', '')")
  end

  after(:all) do
    conn = ActiveRecord::Base.connection
    conn.execute("DROP TABLE IF EXISTS evo_enterprise_tenant_memberships")
    conn.execute("DROP TABLE IF EXISTS evo_enterprise_whitelabel_configs")
    conn.execute("DROP TABLE IF EXISTS evo_enterprise_agencies")
  end

  before do
    conn = ActiveRecord::Base.connection
    conn.execute("TRUNCATE users CASCADE")
    conn.execute("DELETE FROM #{memberships}")
    conn.execute("UPDATE #{whitelabel} SET app_title = '', primary_color = '#22C55E', secondary_color = NULL")
  end

  def whitelabel_row
    ActiveRecord::Base.connection.select_one("SELECT app_title, primary_color FROM #{whitelabel} LIMIT 1")
  end

  it 'creates the first admin with super_admin + the global evolution_admin membership' do
    expect(User.count).to eq(0)

    post '/setup/bootstrap', params: base_params

    expect(response).to have_http_status(:created)

    user = User.find_by(email: 'owner@evo.local')
    expect(user).to be_present
    expect(user.has_role?('super_admin')).to be(true)

    membership = ActiveRecord::Base.connection.select_one(
      "SELECT role, tenant_id FROM #{memberships} WHERE user_id = '#{user.id}'"
    )
    expect(membership).to be_present
    expect(membership['role']).to eq('evolution_admin')
    expect(membership['tenant_id']).to be_nil
  end

  it 'persists the operator brand onto the singleton whitelabel row' do
    post '/setup/bootstrap', params: base_params.merge(app_title: 'Acme', primary_color: '#3366FF')

    expect(response).to have_http_status(:created)
    row = whitelabel_row
    expect(row['app_title']).to eq('Acme')
    expect(row['primary_color']).to eq('#3366FF')
  end

  it 'overwrites only the provided fields (blank leaves the default)' do
    post '/setup/bootstrap', params: base_params.merge(app_title: 'Acme')

    expect(response).to have_http_status(:created)
    row = whitelabel_row
    expect(row['app_title']).to eq('Acme')       # provided → overwritten
    expect(row['primary_color']).to eq('#22C55E') # not provided → default kept
  end

  it 'leaves the whitelabel untouched when no brand is provided' do
    post '/setup/bootstrap', params: base_params

    expect(response).to have_http_status(:created)
    row = whitelabel_row
    expect(row['app_title']).to eq('')
    expect(row['primary_color']).to eq('#22C55E')
  end

  it 'rejects an invalid color with 422 and does not create the admin' do
    post '/setup/bootstrap', params: base_params.merge(primary_color: 'not-a-hex')

    expect(response).to have_http_status(:unprocessable_entity)
    expect(User.count).to eq(0)
  end

  # params.permit lets non-string scalars through; a JSON number reaching the hex
  # validation used to raise (NoMethodError) and 500. It must coerce and 422.
  it 'does not 500 when a color arrives as a non-string JSON number' do
    post '/setup/bootstrap',
         params: base_params.merge(primary_color: 12_345).to_json,
         headers: { 'CONTENT_TYPE' => 'application/json' }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(User.count).to eq(0)
  end
end
