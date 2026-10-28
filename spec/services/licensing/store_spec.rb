# frozen_string_literal: true

require 'rails_helper'

# The licence key must land in runtime_configs, the only place both the web and
# the Sidekiq containers can read. A connection the current thread has not used
# yet (every new Sidekiq job thread) reports active? == false.
RSpec.describe Licensing::Store do
  let(:data_dir) { Dir.mktmpdir }
  let(:store) { described_class.new(data_dir: data_dir) }

  after { FileUtils.remove_entry(data_dir) }

  context 'when the connection has not been used by this thread yet' do
    before { allow(ActiveRecord::Base.connection).to receive(:active?).and_return(false) }

    it 'saves the runtime data to the database' do
      store.save_runtime_data(api_key: 'k' * 64, tier: 'evo-ai-crm-community', customer_id: nil)

      expect(RuntimeConfig.get(described_class::KEY_API_KEY)).to eq('k' * 64)
      expect(RuntimeConfig.get(described_class::KEY_TIER)).to eq('evo-ai-crm-community')
    end

    it 'reads a key another process saved, without a local file' do
      RuntimeConfig.set(described_class::KEY_API_KEY, 'w' * 64)
      RuntimeConfig.set(described_class::KEY_TIER, 'evo-ai-crm-community')

      expect(store.load_runtime_data)
        .to include('k' => 'w' * 64, 't' => 'evo-ai-crm-community')
    end
  end

  it 'falls back to the file when the database is unreachable' do
    allow(ActiveRecord::Base).to receive(:connection).and_raise(ActiveRecord::ConnectionNotEstablished)

    store.save_runtime_data(api_key: 'f' * 64, tier: 'evo-ai-crm-community')

    expect(store.load_runtime_data).to include('k' => 'f' * 64)
  end
end
