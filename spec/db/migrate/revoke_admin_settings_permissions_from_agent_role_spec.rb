# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260626130000_revoke_admin_settings_permissions_from_agent_role.rb')

# Spec for the EVO-1938 data-migration that strips administrative Settings
# resources from the EXISTING system `agent` role on upgrade. Two risks live
# here: it must (1) remove the admin keys so attendants stop seeing admin-only
# screens, and (2) NOT touch custom roles nor the operational permissions the
# chat depends on (labels/canned_responses/macros/message_templates).
RSpec.describe RevokeAdminSettingsPermissionsFromAgentRole do
  let(:migration) { described_class.new }

  before { migration.singleton_class.send(:public, :up, :down) }
  before { load Rails.root.join('db/seeds/rbac.rb') }

  def keys(role)
    role.reload.role_permissions_actions.pluck(:permission_key)
  end

  # Re-grants a representative slice of admin keys to simulate a pre-fix
  # (already-bootstrapped) install where the old seed had granted them.
  def regrant_admin_slice(role)
    %w[integrations.read channels.read agents.read segments.read
       journeys.read campaigns.read working_hours.read].each do |pk|
      role.role_permissions_actions.find_or_create_by!(permission_key: pk)
    end
  end

  describe '#up' do
    it 'revokes the administrative Settings resources from the system agent role' do
      agent = Role.find_by!(key: 'agent')
      regrant_admin_slice(agent)

      migration.up

      expect(keys(agent)).not_to include(
        'integrations.read', 'channels.read', 'agents.read',
        'segments.read', 'journeys.read', 'campaigns.read', 'working_hours.read'
      )
    end

    it 'keeps the operational permissions the chat depends on (incl. teams for the assign-team picker)' do
      agent = Role.find_by!(key: 'agent')
      regrant_admin_slice(agent)

      migration.up

      expect(keys(agent)).to include(
        'labels.read', 'canned_responses.read', 'macros.execute',
        'message_templates.read', 'conversations.read', 'inboxes.read', 'teams.read'
      )
    end

    it 'does not touch a custom (non-system) role that holds the same keys' do
      custom = Role.create!(key: "manager-#{SecureRandom.hex(4)}", name: 'Manager', type: 'account', system: false)
      custom.role_permissions_actions.create!(permission_key: 'integrations.read')
      custom.role_permissions_actions.create!(permission_key: 'segments.read')

      migration.up

      expect(keys(custom)).to include('integrations.read', 'segments.read')
    end

    it 'is idempotent' do
      agent = Role.find_by!(key: 'agent')
      regrant_admin_slice(agent)

      expect do
        migration.up
        migration.up
      end.not_to raise_error
      expect(keys(agent)).not_to include('integrations.read')
    end
  end

  describe '#down' do
    it 'best-effort re-grants the revoked keys to the agent role' do
      agent = Role.find_by!(key: 'agent')
      migration.up

      migration.down

      expect(keys(agent)).to include('integrations.read', 'channels.read', 'campaigns.read')
    end
  end
end
