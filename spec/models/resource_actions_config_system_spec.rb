# frozen_string_literal: true

require 'rails_helper'

# EVO-2070 RBAC catalog hygiene (+ EVO-2072 agents→ai_agents consolidation).
# Two guarantees are locked here:
#   1) the trimmed catalog holds exactly 322 permission keys across 49 resources.
#      277 came from the EVO-2070 hygiene pass; EVO-2127 then added one coarse
#      `write` leaf to each resource that has a manageable (non-system) granular
#      write (45 of 49) to back the role editor's read/write/delete groups →
#      277 + 45 = 322. The 4 all-system/read-only resources (installation_configs,
#      ai_agent_processor, ai_chat_sessions, ai_a2a_protocol) get no write leaf —
#      a coarse write there would render an un-grantable checkbox. NOTE: the
#      earlier 262/47 target assumed ai_tools,
#      ai_folders and ai_mcp_servers were dead; the EVO-2070 audit found all three
#      still enforced by live core/processor routes (ai_tools 8 keys, ai_folders
#      6, ai_mcp_servers 5), so they stay — see the resource_actions_config.rb
#      comments. And
#   2) api_format propagates a `system` flag (default false) so the permissions
#      screen (1.2) can hide system-managed keys from the role editor without
#      dropping them from the catalog.
RSpec.describe ResourceActionsConfig do
  describe 'catalog size after hygiene' do
    it 'exposes exactly 322 permission keys' do
      expect(described_class.all_permission_keys.size).to eq(322)
    end

    it 'exposes exactly 49 resources' do
      expect(described_class.all_resources.size).to eq(49)
    end

    it 'adds a manageable, non-system coarse write to resources with a granular write (EVO-2127)' do
      expect(described_class.valid_permission?('ai_agents.write')).to be(true)
      write = described_class.resource_actions(:ai_agents)[:write]
      expect(write[:system]).to be_falsey # manageable in the role editor
    end

    it 'does NOT add a coarse write to all-system / read-only resources (EVO-2127)' do
      # A coarse write on these would render an un-grantable checkbox that 403s a
      # delegated admin (no granular write source to imply it from).
      %i[installation_configs ai_agent_processor ai_chat_sessions ai_a2a_protocol].each do |key|
        expect(described_class.resource_actions(key)).not_to have_key(:write), "#{key} must not get a coarse write"
        expect(described_class.valid_permission?("#{key}.write")).to be(false)
      end
    end

    it 'dropped the dead/duplicated/consolidated resources' do
      removed = %i[
        permissions channels
        oauth_contacts oauth_agents oauth_pipelines oauth_pipeline_stages
        agent_apikeys agent_folders agent_shared_folders
        team_members live_reports summary_reports reports
        agents
      ]
      expect(described_class::RESOURCES.keys & removed).to be_empty
    end

    it 'kept the survivors that looked removable but are live' do
      # ai_tools/ai_folders/ai_mcp_servers stay: live core/processor enforcement
      # (see resource_actions_config.rb comments — the §A0 audit missed the core).
      %i[oauth_applications ai_agent_processor ai_a2a_protocol ai_agents
         ai_tools ai_folders ai_mcp_servers ai_custom_tools ai_custom_mcp_servers
         teams roles].each do |key|
        expect(described_class::RESOURCES).to have_key(key)
      end
    end
  end

  describe '.api_format system flag' do
    let(:format) { described_class.api_format }

    def nested(resource, action)
      format[:resources][resource][:actions][action]
    end

    def flat(key)
      format[:all_permissions].find { |p| p[:key] == key }
    end

    # The four families whose every action is system-managed (chat runtime and
    # installation config), so the role editor must hide them.
    SYSTEM_KEYS = %w[
      ai_agent_processor.read ai_agent_processor.execute ai_agent_processor.stream
      ai_chat_sessions.read ai_chat_sessions.create ai_chat_sessions.update
      ai_chat_sessions.delete ai_chat_sessions.bulk_delete ai_chat_sessions.metrics
      ai_a2a_protocol.read ai_a2a_protocol.execute ai_a2a_protocol.stream
      ai_a2a_protocol.message_send ai_a2a_protocol.task_management
      installation_configs.manage
    ].freeze

    it 'flags every system-managed key as system in both shapes' do
      SYSTEM_KEYS.each do |key|
        resource, action = key.split('.')
        expect(nested(resource.to_sym, action.to_sym)[:system]).to be(true), "expected #{key} system in nested actions"
        expect(flat(key)[:system]).to be(true), "expected #{key} system in all_permissions"
      end
    end

    it 'defaults ordinary managed keys to system:false' do
      expect(nested(:labels, :create)[:system]).to be(false)
      expect(flat('labels.create')[:system]).to be(false)
    end

    it 'marks exactly the 15 expected system keys' do
      flagged = format[:all_permissions].select { |p| p[:system] }.map { |p| p[:key] }
      expect(flagged).to match_array(SYSTEM_KEYS)
    end
  end
end
