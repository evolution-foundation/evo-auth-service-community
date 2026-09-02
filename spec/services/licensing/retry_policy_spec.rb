# frozen_string_literal: true

require 'rails_helper'

# The cool-down that stops an unlicensed box from hammering the licensing
# server: windows grow exponentially, carry jitter and reset on success.
RSpec.describe Licensing::RetryPolicy do
  include ActiveSupport::Testing::TimeHelpers

  before { Rails.cache.clear }
  after { travel_back }

  it 'allows the very first attempt' do
    expect(described_class.allow_attempt?).to be(true)
    expect(described_class.seconds_until_open).to eq(0)
  end

  it 'closes the window after a failure and reopens it after the wait' do
    freeze_time
    wait = described_class.record_failure!

    expect(described_class.allow_attempt?).to be(false)
    expect(described_class.seconds_until_open).to be_within(1).of(wait)

    travel(wait + 1.second)
    expect(described_class.allow_attempt?).to be(true)
  end

  it 'grows the wait exponentially with jitter and never exceeds MAX_WAIT' do
    freeze_time
    waits = Array.new(6) do
      w = described_class.record_failure!
      travel(w + 1.second)
      w
    end

    base = described_class::BASE_WAIT.to_f
    jitter = described_class::JITTER
    waits.each_with_index do |w, i|
      expected = [base * (2**i), described_class::MAX_WAIT.to_f].min
      expect(w).to be_between(expected * (1 - jitter), expected * (1 + jitter)).inclusive
    end
  end

  it 'never returns a wait above MAX_WAIT, even at maximum jitter' do
    freeze_time
    # Maximum jitter is where a cap applied after the randomization leaks: the
    # +20% would push the real window past the constant that names the ceiling.
    allow(described_class).to receive(:rand).and_return(1.0)
    waits = Array.new(8) { described_class.record_failure! }

    expect(waits).to all(be <= described_class::MAX_WAIT.to_f)
    expect(waits.last).to be_within(0.001).of(described_class::MAX_WAIT.to_f)
  end

  it 'applies jitter both ways instead of a flat wait' do
    freeze_time
    allow(described_class).to receive(:rand).and_return(0.0)
    low = described_class.record_failure!
    described_class.record_success!

    allow(described_class).to receive(:rand).and_return(1.0)
    high = described_class.record_failure!

    base = described_class::BASE_WAIT.to_f
    expect(low).to be_within(0.001).of(base * (1 - described_class::JITTER))
    expect(high).to be_within(0.001).of(base * (1 + described_class::JITTER))
  end

  it 'honours Retry-After as a floor: the window never reopens before it' do
    freeze_time
    wait = described_class.record_failure!(retry_after: 600)

    expect(wait).to be >= 600
    travel(599.seconds)
    expect(described_class.allow_attempt?).to be(false)
    travel(wait - 598)
    expect(described_class.allow_attempt?).to be(true)
  end

  it 'keeps a Retry-After longer than MAX_WAIT: the key outlives the window' do
    freeze_time
    long = (described_class::MAX_WAIT * 3).to_i
    described_class.record_failure!(retry_after: long)

    travel(described_class::MAX_WAIT * 2 + 1.second)
    expect(described_class.allow_attempt?).to be(false)

    travel(described_class::MAX_WAIT + 1.second)
    expect(described_class.allow_attempt?).to be(true)
  end

  it 'resets completely on success' do
    freeze_time
    3.times do
      w = described_class.record_failure!
      travel(w + 1.second)
    end
    described_class.record_success!

    expect(described_class.allow_attempt?).to be(true)
    w = described_class.record_failure!
    expect(w).to be_between(
      described_class::BASE_WAIT.to_f * (1 - described_class::JITTER),
      described_class::BASE_WAIT.to_f * (1 + described_class::JITTER)
    ).inclusive
  end

  it 'lets the ladder decay once the failure counter expires' do
    freeze_time
    3.times { described_class.record_failure! }
    travel(described_class::MAX_WAIT * 2 + 1.second)

    expect(described_class.record_failure!)
      .to be <= described_class::BASE_WAIT.to_f * (1 + described_class::JITTER)
  end

  it 'keeps each window independent so a refused heartbeat does not gate activation' do
    described_class.record_failure!(window: described_class::HEARTBEAT_WINDOW)

    expect(described_class.allow_attempt?(window: described_class::HEARTBEAT_WINDOW)).to be(false)
    expect(described_class.allow_attempt?).to be(true)
  end
end
