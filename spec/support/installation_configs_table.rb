# frozen_string_literal: true

# Creates the installation_configs table in the test database.
# In production this table lives in the shared PostgreSQL database and is
# managed by the CRM service. For tests we replicate just the schema.
RSpec.configure do |config|
  config.before(:suite) do
    ActiveRecord::Base.connection.execute(<<~SQL)
      CREATE TABLE IF NOT EXISTS installation_configs (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        name character varying NOT NULL,
        serialized_value jsonb DEFAULT '{}'::jsonb NOT NULL,
        locked boolean DEFAULT true NOT NULL,
        created_at timestamp without time zone NOT NULL DEFAULT now(),
        updated_at timestamp without time zone NOT NULL DEFAULT now()
      );
      CREATE UNIQUE INDEX IF NOT EXISTS index_installation_configs_on_name
        ON installation_configs (name);
    SQL
  end
end
