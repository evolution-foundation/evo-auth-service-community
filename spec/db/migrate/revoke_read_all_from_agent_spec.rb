# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260817120003_revoke_read_all_from_agent.rb')

# Spec for the CRM-181 data-migration (secure-by-default inbox visibility).
# On upgrade it revokes conversations.read_all from the EXISTING system `agent`
# role. Custom roles and the operational chat permissions stay intact, and the
# rollback must NOT re-grant the key (that would be a privilege escalation).
RSpec.describe RevokeReadAllFromAgent do
  let(:migration) { described_class.new }

  before { load Rails.root.join('db/seeds/rbac.rb') }

  def keys(role)
    role.reload.role_permissions_actions.pluck(:permission_key)
  end

  # Simulate a pre-fix (already-bootstrapped) install: the old seed granted
  # conversations.read_all to the agent.
  def to_pre_fix_state(role)
    described_class::REVOKED_PERMISSIONS.each do |pk|
      next if role.role_permissions_actions.exists?(permission_key: pk)

      role.role_permissions_actions.create!(permission_key: pk)
    end
  end

  describe '#up' do
    it 'revokes conversations.read_all from the system agent role' do
      agent = Role.find_by!(key: 'agent')
      to_pre_fix_state(agent)

      migration.up

      expect(keys(agent)).not_to include('conversations.read_all')
    end

    it 'keeps the operational permissions attendance depends on' do
      agent = Role.find_by!(key: 'agent')
      to_pre_fix_state(agent)

      migration.up

      expect(keys(agent)).to include(
        'conversations.read', 'conversations.create', 'conversations.update',
        'conversations.toggle_status', 'contacts.read', 'inboxes.read', 'users.read'
      )
    end

    it 'does not touch a custom (non-system) role that holds read_all' do
      custom = Role.create!(key: "manager-#{SecureRandom.hex(4)}", name: 'Manager', type: 'account', system: false)
      custom.role_permissions_actions.create!(permission_key: 'conversations.read_all')

      migration.up

      expect(keys(custom)).to include('conversations.read_all')
    end

    it 'leaves account_owner and super_admin read_all intact' do
      migration.up

      expect(keys(Role.find_by!(key: 'account_owner'))).to include('conversations.read_all')
      expect(keys(Role.find_by!(key: 'super_admin'))).to include('conversations.read_all')
    end

    it 'is idempotent' do
      agent = Role.find_by!(key: 'agent')
      to_pre_fix_state(agent)

      expect do
        migration.up
        migration.up
      end.not_to raise_error
      expect(keys(agent)).not_to include('conversations.read_all')
    end

    it 'does not raise while counting agents without inbox membership' do
      # inbox_members is a CRM table; the count is guarded/rescued, so `up`
      # must succeed whether or not the table exists in this schema.
      agent = Role.find_by!(key: 'agent')
      to_pre_fix_state(agent)

      expect { migration.up }.not_to raise_error
    end

    it 'announces that the blast radius was NOT assessed when inbox_members is absent' do
      # The auth schema carries no inbox table, so this is the path a pure-auth
      # install takes. Staying silent here would read as "nothing to worry about".
      # Depends on inbox_members NOT existing in the test database — the block
      # below creates it per example and rolls it back.
      agent = Role.find_by!(key: 'agent')
      to_pre_fix_state(agent)

      expect(migration).to receive(:say).with(/blast radius NOT assessed/, true)

      migration.up
    end

    it 'is a no-op when the agent role is absent' do
      Role.where(key: 'agent').destroy_all

      expect { migration.up }.not_to raise_error
    end

    # inbox_members is a CRM table that this schema never carries, so without a
    # stand-in the count is skipped and the SQL never runs. Creating the table
    # inside the example (rolled back with the transaction) makes the guard pass
    # and pins the query against the CRM schema as mirrored here (a change on the
    # CRM side only shows up once this mirror is updated — a cross-repo contract
    # test is out of reach for this repo).
    describe 'blast-radius telemetry against a real inbox_members table' do
      let(:conn) { ActiveRecord::Base.connection }
      let(:agent_role) { Role.find_by!(key: 'agent') }

      before do
        # Mirrors evo-ai-crm-community db/schema.rb:632-639. The auth schema never
        # carries this table, so a leftover one is a leak, not a shared fixture:
        # drop it instead of tolerating a shape nobody checked.
        conn.drop_table(:inbox_members, if_exists: true)
        conn.create_table(:inbox_members, id: :uuid) do |t|
          t.uuid :user_id, null: false
          t.uuid :inbox_id, null: false
          t.datetime :created_at, precision: nil, null: false
          t.datetime :updated_at, precision: nil, null: false
          t.index %i[inbox_id user_id], unique: true
        end
        to_pre_fix_state(agent_role)
      end

      def build_agent(name)
        user = User.create!(
          name: name, email: "#{name.parameterize}-#{SecureRandom.hex(4)}@example.com",
          password: 'Str0ng!Passw0rd', password_confirmation: 'Str0ng!Passw0rd', confirmed_at: Time.current
        )
        UserRole.create!(user: user, role: agent_role)
        user
      end

      def add_membership(user)
        conn.execute(<<~SQL.squish)
          INSERT INTO inbox_members (id, user_id, inbox_id, created_at, updated_at)
          VALUES (gen_random_uuid(), #{conn.quote(user.id)}, gen_random_uuid(), now(), now())
        SQL
      end

      it 'counts the agent-role users with zero memberships and warns with the exact number' do
        build_agent('Sem Inbox Um')
        build_agent('Sem Inbox Dois')
        add_membership(build_agent('Com Inbox'))

        expect(migration).to receive(:say).with(/CRM-181: 2 agent-role user\(s\) have ZERO inbox memberships/, true)

        migration.up
      end

      it 'says it is safe to revoke once every agent-role user holds a membership' do
        add_membership(build_agent('Com Inbox'))

        expect(migration).to receive(:say).with(/safe to revoke read_all/, true)
        expect(migration).not_to receive(:say).with(/ZERO inbox memberships/, true)

        migration.up
      end

      it 'does not count users outside the agent role' do
        # A user without inbox_members but holding another role is out of scope.
        owner = Role.find_by!(key: 'account_owner')
        user = User.create!(
          name: 'Dona', email: "dona-#{SecureRandom.hex(4)}@example.com",
          password: 'Str0ng!Passw0rd', password_confirmation: 'Str0ng!Passw0rd', confirmed_at: Time.current
        )
        UserRole.create!(user: user, role: owner)
        add_membership(build_agent('Com Inbox'))

        expect(migration).to receive(:say).with(/safe to revoke read_all/, true)

        migration.up
      end

      it 'still revokes read_all after counting' do
        build_agent('Sem Inbox')

        migration.up

        expect(keys(agent_role)).not_to include('conversations.read_all')
      end

      # The CRM owns inbox_members: if it ever renames the column, the count must
      # degrade to a warning and the revoke must still happen — the failed
      # statement runs in a savepoint so it cannot abort the migration.
      it 'warns and still revokes when the CRM column drifted' do
        conn.rename_column(:inbox_members, :user_id, :member_id)
        build_agent('Sem Inbox')

        # The error class and the offending column are the operator's whole lead:
        # a message that only says "could not count" sends nobody anywhere.
        expect(migration).to receive(:say).with(
          /could not count agents without inbox membership \(ActiveRecord::StatementInvalid: .*user_id.*\); revoking read_all anyway/m,
          true
        )

        expect { migration.up }.not_to raise_error
        expect(keys(agent_role)).not_to include('conversations.read_all')
      end

      # db:migrate runs `up` inside a JOINABLE transaction, where the count needs
      # its own savepoint; the fixture transaction here is non-joinable, so it
      # would get one even without `requires_new: true`. Reproducing the joinable
      # shape is what makes dropping that flag fail here instead of in a deploy.
      it 'warns and still revokes inside a joinable transaction (as db:migrate runs it)' do
        conn.rename_column(:inbox_members, :user_id, :member_id)
        build_agent('Sem Inbox')

        expect { conn.transaction(requires_new: true) { migration.up } }.not_to raise_error
        expect(keys(agent_role)).not_to include('conversations.read_all')
      end
    end
  end

  describe '#down' do
    it 'does NOT re-grant read_all (forward-only; re-granting would escalate privilege)' do
      agent = Role.find_by!(key: 'agent')
      to_pre_fix_state(agent)
      migration.up
      expect(keys(agent)).not_to include('conversations.read_all')

      migration.down

      expect(keys(agent)).not_to include('conversations.read_all')
    end
  end
end
