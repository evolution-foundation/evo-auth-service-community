# frozen_string_literal: true

require 'rails_helper'

# CRM-491: a non-recoverable 4xx answers the same on every retry — the chain
# must stop instead of hammering the server; 429 and network errors stay
# retryable (bounded by RETRY_WAITS).
RSpec.describe Licensing::SetupJob do
  include ActiveJob::TestHelper

  let(:args) { { email: 'op@box.test', name: 'Operador', client_ip: nil } }

  before do
    clear_enqueued_jobs
    Licensing::Runtime.context = Licensing::RuntimeContext.new(tier: 't', version: '1')
    allow(Licensing::Store).to receive(:new)
      .and_return(instance_double(Licensing::Store, load_or_create_instance_id: 'instance-1'))
  end

  after { Licensing::Runtime.context = nil }

  it 'stops the chain on a non-recoverable 4xx (:rejected)' do
    allow(Licensing::Setup).to receive(:perform).and_return(:rejected)

    described_class.new.perform(**args)

    expect(enqueued_jobs).to be_empty
  end

  it 'keeps retrying on a transient failure (false), bounded by RETRY_WAITS' do
    allow(Licensing::Setup).to receive(:perform).and_return(false)

    described_class.new.perform(**args, attempt: 0)

    expect(enqueued_jobs.size).to eq(1)
  end

  describe 'Licensing::Setup.perform error classification' do
    before do
      allow(Licensing::Registration).to receive(:geo_lookup).and_return({})
    end

    it 'returns :rejected on 403 and false on 429' do
      allow(Licensing::Registration).to receive(:direct_register)
        .and_raise(Licensing::Transport::ResponseError.new(403, 'forbidden'))
      expect(Licensing::Setup.perform(email: 'e', name: 'n', instance_id: 'i')).to eq(:rejected)

      allow(Licensing::Registration).to receive(:direct_register)
        .and_raise(Licensing::Transport::ResponseError.new(429, 'rate limited'))
      expect(Licensing::Setup.perform(email: 'e', name: 'n', instance_id: 'i')).to be(false)
    end
  end
end
