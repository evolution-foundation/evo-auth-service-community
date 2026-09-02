# frozen_string_literal: true

require 'rails_helper'

# Inside the cool-down window try_reactivate must not touch the network — the
# spiral was every login re-POSTing /v1/activate right after a refusal.
RSpec.describe Licensing::Activation, '.try_reactivate backoff' do
  include ActiveSupport::Testing::TimeHelpers

  let(:store) do
    instance_double(
      Licensing::Store,
      load_runtime_data: { 'k' => 'api-key-123' },
      load_or_create_instance_id: 'instance-1'
    )
  end
  let(:transport) { instance_double(Licensing::Transport) }

  before do
    Rails.cache.clear
    Licensing::Runtime.context = Licensing::RuntimeContext.new(tier: 't', version: '1')
    allow(Licensing::Endpoint).to receive(:resolve_url).and_return('https://licensing.test')
    allow(Licensing::Transport).to receive(:new).and_return(transport)
  end

  after do
    travel_back
    Licensing::Runtime.context = nil
  end

  it 'does not re-POST while the window is closed, and tries again after it opens' do
    freeze_time
    allow(transport).to receive(:post_signed)
      .and_raise(Licensing::Transport::ResponseError.new(429, 'rate limited'))

    expect(described_class.try_reactivate(store: store)).to be(false)
    expect(transport).to have_received(:post_signed).once

    # Window closed: no network call at all.
    expect(described_class.try_reactivate(store: store)).to be(false)
    expect(transport).to have_received(:post_signed).once

    travel(Licensing::RetryPolicy::MAX_WAIT + 1.second)
    described_class.try_reactivate(store: store)
    expect(transport).to have_received(:post_signed).twice
  end

  it 'resets the window on a successful activation' do
    freeze_time
    call = 0
    allow(transport).to receive(:post_signed) do
      call += 1
      raise Licensing::Transport::ResponseError.new(429, 'rate limited') if call == 1

      { 'status' => 'active' }
    end

    described_class.try_reactivate(store: store)
    travel(Licensing::RetryPolicy::MAX_WAIT + 1.second)

    expect(described_class.try_reactivate(store: store)).to be(true)
    expect(Licensing::RetryPolicy.allow_attempt?).to be(true)
    expect(Licensing::Runtime.context.active?).to be(true)
  end
end
