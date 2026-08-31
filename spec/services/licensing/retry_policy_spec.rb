# frozen_string_literal: true

require 'rails_helper'

# CRM-394: the cool-down that stops an unlicensed box from hammering
# /v1/activate on every trigger. Windows grow exponentially with jitter and
# reset on the first success.
RSpec.describe Licensing::RetryPolicy do
  include ActiveSupport::Testing::TimeHelpers

  before { Rails.cache.clear }
  after { travel_back }

  it 'allows the very first attempt' do
    expect(described_class.allow_attempt?).to be(true)
  end

  it 'closes the window after a failure and reopens it after the wait' do
    freeze_time
    wait = described_class.record_failure!

    expect(described_class.allow_attempt?).to be(false)

    travel(wait + 1.second)
    expect(described_class.allow_attempt?).to be(true)
  end

  it 'grows the wait exponentially with jitter, capped at MAX_WAIT' do
    freeze_time
    waits = Array.new(8) do
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
    expect(waits.last).to be <= described_class::MAX_WAIT.to_f * (1 + jitter)
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
end
