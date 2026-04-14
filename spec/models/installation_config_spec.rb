# frozen_string_literal: true

require 'rails_helper'
require 'fernet'

RSpec.describe InstallationConfig do
  let(:encryption_key) { Base64.urlsafe_encode64(SecureRandom.random_bytes(32)) }

  before do
    described_class.reset_encryption_key_cache!
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('ENCRYPTION_KEY').and_return(encryption_key)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('ENCRYPTION_KEY').and_return(encryption_key)
    Rails.cache.clear
  end

  after do
    described_class.reset_encryption_key_cache!
  end

  describe '#value' do
    context 'with a plain (non-secret) config' do
      let!(:config) do
        described_class.create!(
          name: 'SMTP_ADDRESS',
          serialized_value: { 'value' => 'smtp.example.com' }
        )
      end

      it 'returns the raw value without decryption' do
        expect(config.value).to eq('smtp.example.com')
      end
    end

    context 'with a _SECRET key and encrypted value' do
      let(:plaintext) { 'super-secret-password' }
      let(:encrypted) { Fernet.generate(encryption_key, plaintext) }
      let!(:config) do
        described_class.create!(
          name: 'SMTP_PASSWORD_SECRET',
          serialized_value: { 'value' => encrypted }
        )
      end

      it 'decrypts the Fernet token' do
        expect(config.value).to eq(plaintext)
      end
    end

    context 'with a _SECRET key but plain (non-Fernet) value' do
      let!(:config) do
        described_class.create!(
          name: 'SOME_API_SECRET',
          serialized_value: { 'value' => 'not-a-fernet-token' }
        )
      end

      it 'returns the value as-is (no decryption attempt)' do
        expect(config.value).to eq('not-a-fernet-token')
      end
    end

    context 'with nil serialized_value content' do
      let!(:config) do
        described_class.create!(
          name: 'EMPTY_CONFIG',
          serialized_value: { 'value' => nil }
        )
      end

      it 'returns nil' do
        expect(config.value).to be_nil
      end
    end
  end

  describe '#sensitive?' do
    it 'returns true for keys ending in _SECRET' do
      config = described_class.new(name: 'SMTP_PASSWORD_SECRET')
      expect(config.sensitive?).to be true
    end

    it 'returns false for other keys' do
      config = described_class.new(name: 'SMTP_ADDRESS')
      expect(config.sensitive?).to be false
    end
  end

  describe '.get_value' do
    let!(:config) do
      described_class.create!(
        name: 'SMTP_PORT',
        serialized_value: { 'value' => '465' }
      )
    end

    it 'returns the value for an existing key' do
      expect(described_class.get_value('SMTP_PORT')).to eq('465')
    end

    it 'returns nil for a missing key' do
      expect(described_class.get_value('NONEXISTENT')).to be_nil
    end

    it 'caches the result for 60 seconds' do
      # First call populates cache
      described_class.get_value('SMTP_PORT')

      # Update DB directly — cache should still return old value
      config.update_column(:serialized_value, { 'value' => '587' })

      expect(described_class.get_value('SMTP_PORT')).to eq('465')
    end

    it 'returns fresh value after cache expires' do
      described_class.get_value('SMTP_PORT')

      config.update_column(:serialized_value, { 'value' => '587' })

      # Clear cache to simulate expiry
      Rails.cache.delete('installation_config:SMTP_PORT')

      expect(described_class.get_value('SMTP_PORT')).to eq('587')
    end

    it 'handles database errors gracefully' do
      allow(described_class).to receive(:find_by).and_raise(ActiveRecord::StatementInvalid.new('connection lost'))

      expect(described_class.get_value('SMTP_PORT')).to be_nil
    end

    it 'caches nil for missing keys to avoid repeated DB hits' do
      expect(described_class).to receive(:find_by).with(name: 'NONEXISTENT').once.and_return(nil)

      described_class.get_value('NONEXISTENT')
      described_class.get_value('NONEXISTENT') # second call should hit cache, not DB
    end
  end
end
