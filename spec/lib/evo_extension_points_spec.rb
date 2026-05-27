# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EvoExtensionPoints do
  after do
    EvoExtensionPoints::KNOWN_KEYS.each { |k| EvoExtensionPoints.reset(k) }
  end

  # ---------------------------- Registration API ---------------------------

  describe '.replace' do
    it 'raises KeyError on an unknown key' do
      expect { described_class.replace(:not_a_thing) { :noop } }
        .to raise_error(KeyError)
    end

    it 'raises ArgumentError when no block is given' do
      expect { described_class.replace(:token_claims) }
        .to raise_error(ArgumentError)
    end

    it 'raises ArgumentError when the block arity is incompatible' do
      # :token_claims expects arity 1
      expect { described_class.replace(:token_claims) { :no_args } }
        .to raise_error(ArgumentError, /arity/)
    end

    it 'returns nil on success' do
      result = described_class.replace(:token_claims) { |_user| {} }
      expect(result).to be_nil
    end

    it 'is last-write-wins' do
      described_class.replace(:token_claims) { |_user| { 'a' => 1 } }
      described_class.replace(:token_claims) { |_user| { 'b' => 2 } }
      expect(described_class::TokenClaims.claims_for(Object.new))
        .to eq({ 'b' => 2 })
    end
  end

  describe '.reset' do
    it 'raises KeyError on an unknown key' do
      expect { described_class.reset(:not_a_thing) }.to raise_error(KeyError)
    end

    it 'clears only the named extension point' do
      described_class.replace(:token_claims) { |_user| { 'a' => 1 } }
      described_class.replace(:login_gate) { |_user, **_ctx| [:deny, :blocked] }
      described_class.reset(:token_claims)

      expect(described_class::TokenClaims.claims_for(Object.new)).to eq({})
      expect(described_class::LoginGate.check(Object.new)).to eq([:deny, :blocked])
    end
  end

  describe 'per-EP VERSION constants' do
    it 'exposes a VERSION on every sub-module and no aggregate constant' do
      expect(described_class::AuthBridge::VERSION).to eq('1.1.0')
      expect(described_class::TokenClaims::VERSION).to eq('1.0.0')
      expect(described_class::LoginGate::VERSION).to eq('1.0.0')
      expect(described_class.const_defined?(:EXTENSION_POINTS_VERSION)).to be(false)
    end
  end

  # ----------------------------- AuthBridge --------------------------------

  describe EvoExtensionPoints::AuthBridge do
    after { ::Current.reset if defined?(::Current) }

    it 'current_user returns Current.user when set' do
      sentinel = Object.new
      ::Current.user = sentinel
      expect(described_class.current_user).to equal(sentinel)
    end

    it 'current_user returns nil outside a request scope' do
      ::Current.reset
      expect(described_class.current_user).to be_nil
    end

    it 'sign_in_user populates Current.user as the default behaviour' do
      ::Current.reset
      user = Object.new
      result = described_class.sign_in_user(user)
      expect(result).to equal(user)
      expect(::Current.user).to equal(user)
    end

    it 'sign_out clears Current.user as the default behaviour' do
      user = Object.new
      ::Current.user = user
      described_class.sign_out(user)
      expect(::Current.user).to be_nil
    end

    it 'honors a replace override on current_user' do
      sentinel = Object.new
      EvoExtensionPoints.replace(:auth_bridge_current_user) { sentinel }
      expect(described_class.current_user).to equal(sentinel)
    end

    it 'honors a replace override on create_user' do
      EvoExtensionPoints.replace(:auth_bridge_create_user) do |email:, password:, attrs: {}|
        { email: email, password: password, attrs: attrs }
      end
      result = described_class.create_user(email: 'a@b.test', password: 'pw', attrs: { role: 'agent' })
      expect(result).to eq(email: 'a@b.test', password: 'pw', attrs: { role: 'agent' })
    end

    it 'honors a replace override on sign_in_user' do
      seen = []
      EvoExtensionPoints.replace(:auth_bridge_sign_in_user) { |user| seen << user }
      described_class.sign_in_user(:user_42)
      expect(seen).to eq([:user_42])
    end

    it 'honors a replace override on sign_out' do
      seen = []
      EvoExtensionPoints.replace(:auth_bridge_sign_out) { |user| seen << user }
      described_class.sign_out(:user_42)
      expect(seen).to eq([:user_42])
    end

    # ------- v1.1.0 additions -------

    it 'find_user_by_email returns nil when no override is registered and no row matches' do
      expect(described_class.find_user_by_email('missing@example.test')).to be_nil
    end

    it 'honors a replace override on find_user_by_email' do
      sentinel = Object.new
      EvoExtensionPoints.replace(:auth_bridge_find_user_by_email) { |_email| sentinel }
      expect(described_class.find_user_by_email('any@example.test')).to equal(sentinel)
    end

    it 'sign_in_request forwards to the Warden proxy on the request env (default impl)' do
      user = Object.new
      warden = double('warden')
      expect(warden).to receive(:set_user).with(user, scope: :user)
      request = double('request', env: { 'warden' => warden })

      described_class.sign_in_request(user, request)
      expect(::Current.user).to equal(user)
    end

    it 'sign_in_request is a no-op on warden when the request has none (still sets Current.user)' do
      user = Object.new
      request = double('request', env: {})
      expect { described_class.sign_in_request(user, request) }.not_to raise_error
      expect(::Current.user).to equal(user)
    end

    it 'honors a replace override on sign_in_request' do
      seen = []
      EvoExtensionPoints.replace(:auth_bridge_sign_in_request) { |user, request| seen << [user, request] }
      described_class.sign_in_request(:user_42, :req_stub)
      expect(seen).to eq([[:user_42, :req_stub]])
    end
  end

  # ----------------------------- TokenClaims -------------------------------

  describe EvoExtensionPoints::TokenClaims do
    it 'returns an empty hash by default' do
      expect(described_class.claims_for(Object.new)).to eq({})
    end

    it 'honors a replace override and returns non-reserved keys verbatim' do
      EvoExtensionPoints.replace(:token_claims) do |user|
        { 'audience' => 'my_consumer', 'user_object' => user }
      end
      user = Object.new
      result = described_class.claims_for(user)
      expect(result).to eq('audience' => 'my_consumer', 'user_object' => user)
    end

    it 'raises ReservedKeyError in test env when consumer returns reserved JWT keys' do
      EvoExtensionPoints.replace(:token_claims) do |_user|
        { 'audience' => 'my_consumer', 'aud' => 'hijacked', 'exp' => 9_999_999_999 }
      end
      expect { described_class.claims_for(Object.new) }
        .to raise_error(described_class::ReservedKeyError) do |err|
          expect(err.reserved_keys).to contain_exactly('aud', 'exp')
        end
    end

    it 'drops reserved keys silently in non-strict env (simulated)' do
      EvoExtensionPoints.replace(:token_claims) do |_user|
        { 'audience' => 'my_consumer', 'aud' => 'hijacked' }
      end

      original_env = Rails.env
      Rails.env = ActiveSupport::EnvironmentInquirer.new('production')
      begin
        result = described_class.claims_for(Object.new)
        expect(result).to eq('audience' => 'my_consumer')
      ensure
        Rails.env = original_env
      end
    end
  end

  # ------------------------------ LoginGate --------------------------------

  describe EvoExtensionPoints::LoginGate do
    it 'returns :allow by default' do
      expect(described_class.check(Object.new)).to eq(:allow)
    end

    it 'forwards context kwargs to the default impl' do
      expect(described_class.check(Object.new, ip: '127.0.0.1', user_agent: 'rspec'))
        .to eq(:allow)
    end

    it 'honors a replace override returning :allow' do
      EvoExtensionPoints.replace(:login_gate) { |_user, **_ctx| :allow }
      expect(described_class.check(Object.new)).to eq(:allow)
    end

    it 'honors a replace override returning [:deny, reason_symbol]' do
      EvoExtensionPoints.replace(:login_gate) do |_user, **context|
        context[:blocked] ? [:deny, :blocked_by_consumer] : :allow
      end
      expect(described_class.check(Object.new)).to eq(:allow)
      expect(described_class.check(Object.new, blocked: true))
        .to eq([:deny, :blocked_by_consumer])
    end

    it 'fails closed when the override returns an unsupported value' do
      EvoExtensionPoints.replace(:login_gate) { |_user, **_ctx| true } # not :allow, not [:deny, sym]
      expect(described_class.check(Object.new)).to eq([:deny, :gate_invalid_return])
    end

    it 'fails closed when the override returns nil' do
      EvoExtensionPoints.replace(:login_gate) { |_user, **_ctx| nil }
      expect(described_class.check(Object.new)).to eq([:deny, :gate_invalid_return])
    end

    it 'fails closed when the override returns a deny with a non-symbol reason' do
      EvoExtensionPoints.replace(:login_gate) { |_user, **_ctx| [:deny, 'string_reason'] }
      expect(described_class.check(Object.new)).to eq([:deny, :gate_invalid_return])
    end

    it 'fails closed when the override raises an exception' do
      EvoExtensionPoints.replace(:login_gate) { |_user, **_ctx| raise 'boom' }
      expect(described_class.check(Object.new)).to eq([:deny, :gate_exception])
    end
  end
end
