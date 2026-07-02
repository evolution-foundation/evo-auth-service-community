# frozen_string_literal: true

begin
  require 'rails_helper'
rescue LoadError
  RSpec.describe 'AuthHelper#cookie_domain' do
    it 'has spec scaffold ready' do
      skip 'rails_helper is not available in this workspace snapshot'
    end
  end
end

return unless defined?(Rails)

RSpec.describe AuthHelper do
  let(:dummy_class) do
    Class.new do
      include AuthHelper
      attr_accessor :request
    end
  end
  let(:instance) { dummy_class.new }

  def cookie_domain_for(host)
    instance.request = double('request', host: host)
    instance.cookie_domain
  end

  describe '#cookie_domain' do
    context 'when host resolution applies (production-like env)' do
      before { allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production')) }

      it 'returns the registrable domain for a .com.br ccTLD (not .com.br)' do
        expect(cookie_domain_for('evocrm-evo-auth.cap.refletia.com.br')).to eq('.refletia.com.br')
      end

      it 'returns the registrable domain for a plain .com host' do
        expect(cookie_domain_for('app.exemplo.com')).to eq('.exemplo.com')
      end

      it 'handles other 2-level ccTLDs (.co.uk)' do
        expect(cookie_domain_for('auth.acme.co.uk')).to eq('.acme.co.uk')
      end

      it 'returns nil (host-only) for localhost' do
        expect(cookie_domain_for('localhost')).to be_nil
      end

      it 'returns nil (host-only) for an IP address' do
        expect(cookie_domain_for('192.168.0.10')).to be_nil
      end
    end

    context 'with COOKIE_DOMAIN env override' do
      before { allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production')) }

      it 'uses the explicit env value regardless of host' do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('COOKIE_DOMAIN').and_return('.custom.com.br')
        expect(cookie_domain_for('whatever.refletia.com.br')).to eq('.custom.com.br')
      end
    end
  end
end
