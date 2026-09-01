# frozen_string_literal: true

require 'rails_helper'

# Exactly ONE heartbeat chain per box: schedule! rotates a generation and any
# chain that does not match it dies on its next tick instead of rescheduling.
RSpec.describe Licensing::Heartbeat do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  before do
    Rails.cache.clear
    clear_enqueued_jobs
  end

  after do
    travel_back
    Licensing::Runtime.context = nil
  end

  def active_context
    ctx = Licensing::RuntimeContext.new(tier: 't', version: '1')
    ctx.activate!(api_key: 'k', instance_id: 'i')
    ctx
  end

  describe '.schedule!' do
    it 'rotates the generation and enqueues the job carrying it' do
      generation = described_class.schedule!

      expect(described_class.current_generation).to eq(generation)
      expect(Licensing::HeartbeatJob).to have_been_enqueued.with(generation)
    end

    it 'invalidates the previous chain: two schedules leave only the last generation alive' do
      first = described_class.schedule!
      second = described_class.schedule!

      expect(described_class.chain_alive?(first)).to be(false)
      expect(described_class.chain_alive?(second)).to be(true)
    end
  end

  describe '.chain_alive?' do
    it 'is false for a legacy job with no generation' do
      described_class.schedule!
      expect(described_class.chain_alive?(nil)).to be(false)
    end

    it 'adopts the calling generation when the cache lost the current one' do
      expect(described_class.chain_alive?('orphan-gen')).to be(true)
      expect(described_class.current_generation).to eq('orphan-gen')
    end
  end

  describe '.next_interval' do
    it 'jitters around INTERVAL within the configured fraction' do
      intervals = Array.new(50) { described_class.next_interval }
      low  = described_class::INTERVAL * (1 - described_class::JITTER)
      high = described_class::INTERVAL * (1 + described_class::JITTER)
      expect(intervals).to all(be_between(low, high).inclusive)
    end

    it 'moves both ways instead of returning a flat INTERVAL' do
      allow(described_class).to receive(:rand).and_return(0.0)
      expect(described_class.next_interval)
        .to be_within(0.001).of(described_class::INTERVAL * (1 - described_class::JITTER))

      allow(described_class).to receive(:rand).and_return(1.0)
      expect(described_class.next_interval)
        .to be_within(0.001).of(described_class::INTERVAL * (1 + described_class::JITTER))
    end
  end

  describe '.ping backoff' do
    let(:transport) { instance_double(Licensing::Transport) }

    before do
      Licensing::Runtime.context = active_context
      allow(Licensing::Endpoint).to receive(:resolve_url).and_return('https://licensing.test')
      allow(Licensing::Transport).to receive(:new).and_return(transport)
    end

    it 'honours a Retry-After on the heartbeat instead of ticking at INTERVAL' do
      allow(transport).to receive(:post_signed)
        .and_raise(Licensing::Transport::ResponseError.new(429, 'rate limited', retry_after: 3600))

      described_class.ping

      expect(described_class.next_interval).to be_within(5).of(3600)
    end

    it 'grows the interval on consecutive refusals and resets it on a good ping' do
      allow(transport).to receive(:post_signed)
        .and_raise(Licensing::Transport::ResponseError.new(500, 'boom'))
      2.times { described_class.ping }

      ceiling = described_class::INTERVAL * (1 + described_class::JITTER)
      expect(described_class.next_interval).to be > ceiling

      allow(transport).to receive(:post_signed).and_return({ 'status' => 'active' })
      described_class.ping

      expect(described_class.next_interval).to be <= ceiling
    end

    it 'keeps the activation window untouched when only the heartbeat is refused' do
      allow(transport).to receive(:post_signed)
        .and_raise(Licensing::Transport::ResponseError.new(429, 'rate limited'))

      described_class.ping

      expect(Licensing::RetryPolicy.allow_attempt?).to be(true)
    end
  end

  describe Licensing::HeartbeatJob do
    it 'a legacy job (no generation) neither pings nor reschedules — the cleanup path' do
      Licensing::Runtime.context = active_context
      allow(Licensing::Heartbeat).to receive(:ping)

      Licensing::HeartbeatJob.new.perform

      expect(Licensing::Heartbeat).not_to have_received(:ping)
      expect(enqueued_jobs).to be_empty
    end

    it 'a stale generation dies silently even with an active license' do
      Licensing::Runtime.context = active_context
      stale = Licensing::Heartbeat.schedule!
      clear_enqueued_jobs
      Licensing::Heartbeat.schedule!
      clear_enqueued_jobs
      allow(Licensing::Heartbeat).to receive(:ping)

      Licensing::HeartbeatJob.new.perform(stale)

      expect(Licensing::Heartbeat).not_to have_received(:ping)
      expect(enqueued_jobs).to be_empty
    end

    it 'the current chain pings and reschedules itself with the same generation, never immediately' do
      freeze_time
      Licensing::Runtime.context = active_context
      generation = Licensing::Heartbeat.schedule!
      clear_enqueued_jobs
      allow(Licensing::Heartbeat).to receive(:ping)

      Licensing::HeartbeatJob.new.perform(generation)

      expect(Licensing::Heartbeat).to have_received(:ping).once
      expect(Licensing::HeartbeatJob).to have_been_enqueued.with(generation)

      scheduled_at = enqueued_jobs.last[:at]
      low  = Time.current + (Licensing::Heartbeat::INTERVAL * (1 - Licensing::Heartbeat::JITTER))
      high = Time.current + (Licensing::Heartbeat::INTERVAL * (1 + Licensing::Heartbeat::JITTER))
      expect(scheduled_at).to be_between(low.to_f, high.to_f).inclusive
    end

    it 'does not reschedule when the license is not active' do
      Licensing::Runtime.context = Licensing::RuntimeContext.new(tier: 't', version: '1')
      generation = Licensing::Heartbeat.schedule!
      clear_enqueued_jobs
      allow(Licensing::Heartbeat).to receive(:ping)

      Licensing::HeartbeatJob.new.perform(generation)

      expect(enqueued_jobs).to be_empty
    end
  end
end
