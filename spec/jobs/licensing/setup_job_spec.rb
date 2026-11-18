# frozen_string_literal: true

require 'rails_helper'

# A non-recoverable 4xx answers the same on every retry so the chain stops;
# 429 and network errors stay retryable, bounded by RETRY_WAITS.
RSpec.describe Licensing::SetupJob do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:args) { { email: 'op@box.test', name: 'Operador', client_ip: nil } }

  let(:store) { instance_double(Licensing::Store, load_or_create_instance_id: 'instance-1', load_runtime_data: nil) }

  before do
    Rails.cache.clear
    clear_enqueued_jobs
    Licensing::Runtime.context = Licensing::RuntimeContext.new(tier: 't', version: '1')
    allow(Licensing::Store).to receive(:new).and_return(store)
  end

  def enqueued_args
    enqueued_jobs.last[:args].first.symbolize_keys.except(:_aj_ruby2_keywords)
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

  it 'schedules the retry after the backoff window its own failure opened' do
    allow(Licensing::Registration).to receive(:geo_lookup).and_return({})
    allow(Licensing::Registration).to receive(:direct_register)
      .and_raise(Licensing::Transport::NetworkError, 'unreachable')

    described_class.new.perform(**args, attempt: 0)
    retry_at = Time.zone.at(enqueued_jobs.last[:at])
    clear_enqueued_jobs

    travel_to(retry_at, with_usec: true) { described_class.new.perform(**args, attempt: 1) }

    expect(Licensing::Registration).to have_received(:direct_register).twice
    expect(enqueued_jobs.size).to eq(1)
  end

  it 'does not run inside a closed activation window' do
    Licensing::RetryPolicy.record_failure!
    allow(Licensing::Setup).to receive(:perform)

    described_class.new.perform(**args)

    expect(Licensing::Setup).not_to have_received(:perform)
    expect(enqueued_jobs).to be_empty
  end

  it 'keeps a retry that finds the window closed again waiting for it to open' do
    Licensing::RetryPolicy.record_failure!
    allow(Licensing::Setup).to receive(:perform)

    described_class.new.perform(**args, attempt: 2)

    expect(Licensing::Setup).not_to have_received(:perform)
    expect(enqueued_args).to include(attempt: 2)
    expect(Licensing::RetryPolicy.allow_attempt?(now: Time.zone.at(enqueued_jobs.last[:at]))).to be(true)
  end

  it 'ends the chain once another process has stored a license' do
    allow(Licensing::Setup).to receive(:perform).and_return(false)
    described_class.new.perform(**args, attempt: 0)
    retry_args = enqueued_args
    clear_enqueued_jobs

    allow(store).to receive(:load_runtime_data).and_return({ 'k' => 'activated-elsewhere' })
    described_class.new.perform(**retry_args)

    expect(Licensing::Setup).to have_received(:perform).once
    expect(enqueued_jobs).to be_empty
  end

  it 'keeps retrying a chain begun with a stored key while that key is unchanged' do
    allow(store).to receive(:load_runtime_data).and_return({ 'k' => 'stale-key' })
    allow(Licensing::Setup).to receive(:perform).and_return(false)
    described_class.new.perform(**args, attempt: 0)
    retry_args = enqueued_args
    clear_enqueued_jobs

    described_class.new.perform(**retry_args)

    expect(retry_args[:key_digest]).not_to include('stale-key')
    expect(Licensing::Setup).to have_received(:perform).twice
    expect(enqueued_args).to include(attempt: 2, key_digest: retry_args[:key_digest])
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

    it 'closes the shared window on a refused register, honouring Retry-After' do
      allow(Licensing::Registration).to receive(:direct_register)
        .and_raise(Licensing::Transport::ResponseError.new(429, 'rate limited', retry_after: 900))

      Licensing::Setup.perform(email: 'e', name: 'n', instance_id: 'i')

      expect(Licensing::RetryPolicy.allow_attempt?).to be(false)
      expect(Licensing::RetryPolicy.seconds_until_open).to be_within(5).of(900)
    end

    it 'reopens the window once the register succeeds' do
      Licensing::RetryPolicy.record_failure!
      allow(Licensing::Store).to receive(:new).and_return(
        instance_double(Licensing::Store, load_or_create_instance_id: 'instance-1', save_runtime_data: true)
      )
      allow(Licensing::Heartbeat).to receive(:schedule!)
      allow(Licensing::Registration).to receive(:direct_register)
        .and_return({ 'api_key' => 'k', 'tier' => 't', 'customer_id' => 'c' })

      expect(Licensing::Setup.perform(email: 'e', name: 'n', instance_id: 'i')).to be(true)
      expect(Licensing::RetryPolicy.allow_attempt?).to be(true)
    end
  end
end
