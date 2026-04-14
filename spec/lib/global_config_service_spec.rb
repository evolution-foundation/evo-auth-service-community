# frozen_string_literal: true

require 'rails_helper'
require 'fernet'

RSpec.describe GlobalConfigService do
  let(:encryption_key) { Base64.urlsafe_encode64(SecureRandom.random_bytes(32)) }

  before do
    InstallationConfig.reset_encryption_key_cache!
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('ENCRYPTION_KEY').and_return(encryption_key)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('ENCRYPTION_KEY').and_return(encryption_key)
    Rails.cache.clear
  end

  after do
    InstallationConfig.reset_encryption_key_cache!
  end

  describe '.load' do
    context 'when value exists in installation_configs' do
      before do
        InstallationConfig.create!(
          name: 'SMTP_ADDRESS',
          serialized_value: { 'value' => 'smtp.admin.com' }
        )
      end

      it 'returns the installation_config value' do
        expect(described_class.load('SMTP_ADDRESS')).to eq('smtp.admin.com')
      end

      it 'takes priority over runtime_configs' do
        RuntimeConfig.create!(key: 'SMTP_ADDRESS', value: 'smtp.runtime.com')
        expect(described_class.load('SMTP_ADDRESS')).to eq('smtp.admin.com')
      end

      it 'takes priority over ENV' do
        allow(ENV).to receive(:fetch).with('SMTP_ADDRESS', nil).and_return('smtp.env.com')
        expect(described_class.load('SMTP_ADDRESS')).to eq('smtp.admin.com')
      end
    end

    context 'when value exists only in runtime_configs' do
      before do
        RuntimeConfig.create!(key: 'account', value: '{"name":"test"}')
      end

      it 'returns the runtime_config value' do
        expect(described_class.load('account')).to eq('{"name":"test"}')
      end

      it 'takes priority over ENV' do
        allow(ENV).to receive(:fetch).with('account', nil).and_return('env-val')
        expect(described_class.load('account')).to eq('{"name":"test"}')
      end
    end

    context 'when value exists only in ENV' do
      it 'returns the ENV value' do
        allow(ENV).to receive(:fetch).with('SOME_KEY', nil).and_return('env-value')
        expect(described_class.load('SOME_KEY')).to eq('env-value')
      end
    end

    context 'when value does not exist anywhere' do
      it 'returns the default value' do
        expect(described_class.load('MISSING_KEY', 'fallback')).to eq('fallback')
      end

      it 'returns nil when no default is provided' do
        expect(described_class.load('MISSING_KEY')).to be_nil
      end
    end

    context 'when database is unavailable' do
      before do
        allow(InstallationConfig).to receive(:get_value).and_raise(StandardError.new('DB down'))
      end

      it 'falls back to ENV' do
        allow(ENV).to receive(:fetch).with('FALLBACK_KEY', 'default').and_return('env-fallback')
        expect(described_class.load('FALLBACK_KEY', 'default')).to eq('env-fallback')
      end
    end

    context 'with encrypted _SECRET values in installation_configs' do
      let(:plaintext) { 'my-smtp-password' }
      let(:encrypted) { Fernet.generate(encryption_key, plaintext) }

      before do
        InstallationConfig.create!(
          name: 'SMTP_PASSWORD_SECRET',
          serialized_value: { 'value' => encrypted }
        )
      end

      it 'returns the decrypted value' do
        expect(described_class.load('SMTP_PASSWORD_SECRET')).to eq(plaintext)
      end
    end
  end
end
