# frozen_string_literal: true

require 'rails_helper'

# CRM-394: exactly ONE heartbeat chain per box. Every scheduling site used to
# start its own immortal self-rescheduling chain (and Sidekiq persists them
# across restarts), which multiplied the fleet's heartbeat traffic by the
# number of boots. schedule! rotates a generation; any chain that does not
# match it dies on its next tick.
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
