# frozen_string_literal: true

require 'rails_helper'

# The cached registration URL is only valid for the redirect_uri it was minted
# with: serving it for another strands the OAuth with the key never exchanged.
RSpec.describe 'GET /setup/register redirect_uri cache', type: :request do
  let(:ctx) { Licensing::RuntimeContext.new(tier: 't', version: '1') }

  before do
    Rails.cache.clear
    Licensing::Runtime.context = ctx
    allow(Licensing::Store).to receive(:new)
      .and_return(instance_double(Licensing::Store, load_or_create_instance_id: 'instance-1',
                                                    load_runtime_data: nil))
    allow(Licensing::Registration).to receive(:init_register)
      .and_return({ 'register_url' => 'https://portal.test/r/1', 'token' => 'tok' })
  end

  after { Licensing::Runtime.context = nil }

  it 'reuses the cached URL only for the same redirect_uri and re-inits when it changes' do
    2.times { get '/setup/register', params: { redirect_uri: 'https://box.test/setup/activate' } }
    expect(Licensing::Registration).to have_received(:init_register).once

    get '/setup/register', params: { redirect_uri: 'https://other.test/setup/activate' }
    expect(Licensing::Registration).to have_received(:init_register).twice
    expect(Licensing::Registration).to have_received(:init_register)
      .with(hash_including(redirect_uri: 'https://other.test/setup/activate'))
    expect(response).to have_http_status(:ok)
  end

  it 're-inits when the cached URL was minted without a redirect_uri and one arrives' do
    get '/setup/register'
    get '/setup/register', params: { redirect_uri: 'https://box.test/setup/activate' }

    expect(Licensing::Registration).to have_received(:init_register).twice
  end
end
