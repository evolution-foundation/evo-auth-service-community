# frozen_string_literal: true

require 'rails_helper'

# CRM-234 defeito 3: GET /setup/register cached the registration link forever.
# The licensing token expires (~5 min) and /register/init returns no expiry, so a
# link handed back long after issuance answered "licenca expirada" when the
# operator finally clicked it (SendGrid mail, slow tab). #register must reissue a
# stale link — while still caching a fresh one so the frontend poll neither churns
# the token the open tab is using nor hammers the licensing server.
RSpec.describe 'GET /setup/register', type: :request do
  # A minimal stand-in for RuntimeContext with real, settable reg_* state.
  ctx_class = Class.new do
    attr_accessor :reg_url, :reg_token, :reg_issued_at
    def active?      = false
    def tier         = 'evo-ai-crm-community'
    def version      = 'v1'
    def instance_id  = 'inst-abc'
  end

  let(:ctx) { ctx_class.new }

  before do
    allow(Licensing::Runtime).to receive(:context).and_return(ctx)
    call = 0
    allow(Licensing::Registration).to receive(:init_register) do
      call += 1
      { 'register_url' => "https://license.example/register?token=tok#{call}", 'token' => "tok#{call}" }
    end
  end

  def token_in(response)
    JSON.parse(response.body)['register_url'].to_s[/token=(\w+)/, 1]
  end

  it 'issues a fresh link and records when, when nothing is cached' do
    get '/setup/register'

    expect(response).to have_http_status(:ok)
    expect(token_in(response)).to eq('tok1')
    expect(ctx.reg_issued_at).to be_within(5.seconds).of(Time.current)
    expect(Licensing::Registration).to have_received(:init_register).once
  end

  it 'reuses the cached link while it is still fresh (no reissue)' do
    ctx.reg_url = 'https://license.example/register?token=cached'
    ctx.reg_issued_at = 30.seconds.ago

    get '/setup/register'

    expect(token_in(response)).to eq('cached')
    expect(Licensing::Registration).not_to have_received(:init_register)
  end

  it 'reissues once the cached link is past the TTL (the defeito 3 fix)' do
    ctx.reg_url = 'https://license.example/register?token=stale'
    ctx.reg_issued_at = (SetupController::REG_URL_TTL + 1.minute).ago

    get '/setup/register'

    expect(token_in(response)).to eq('tok1')          # a fresh token, not the stale one
    expect(ctx.reg_issued_at).to be_within(5.seconds).of(Time.current)
    expect(Licensing::Registration).to have_received(:init_register).once
  end

  it 'reissues a link with no issued_at (upgrade from before the fix)' do
    ctx.reg_url = 'https://license.example/register?token=legacy'
    ctx.reg_issued_at = nil

    get '/setup/register'

    expect(token_in(response)).to eq('tok1')
  end
end
