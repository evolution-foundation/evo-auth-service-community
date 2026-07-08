# frozen_string_literal: true

require 'rails_helper'

# EVO-2070 RBAC catalog hygiene. Two guarantees are locked here:
#   1) the trimmed catalog holds exactly 270 permission keys across 48 resources
#      (the dead/duplicated resources are gone, the survivors stay). NOTE: the
#      spec's 262/47 target assumed ai_tools was dead; the EVO-2070 audit found
#      it still enforced by live processor endpoints, so ai_tools (8 keys) stays
#      — see the story Dev Agent Record. Removing it is deferred to a follow-up
#      that also repoints the processor. And
#   2) api_format propagates a `system` flag (default false) so the permissions
#      screen (1.2) can hide system-managed keys from the role editor without
#      dropping them from the catalog.
RSpec.describe ResourceActionsConfig do
  describe 'catalog size after hygiene' do
    it 'exposes exactly 270 permission keys' do
      expect(described_class.all_permission_keys.size).to eq(270)
    end

    it 'exposes exactly 48 resources' do
      expect(described_class.all_resources.size).to eq(48)
    end

    it 'dropped the dead/duplicated/consolidated resources' do
      removed = %i[
        permissions ai_folders ai_mcp_servers channels
        oauth_contacts oauth_agents oauth_pipelines oauth_pipeline_stages
        agent_apikeys agent_folders agent_shared_folders
        team_members live_reports summary_reports reports
      ]
      expect(described_class::RESOURCES.keys & removed).to be_empty
    end

    it 'kept the survivors that looked removable but are live' do
      # ai_tools stays: live processor enforcement (see story Dev Agent Record).
      %i[oauth_applications ai_agent_processor ai_a2a_protocol agents ai_agents
         ai_tools ai_custom_tools ai_custom_mcp_servers teams roles].each do |key|
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
