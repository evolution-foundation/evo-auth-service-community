# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AccessToken do
  let(:user) do
    User.create!(
      name: 'Token Owner',
      email: "owner-#{SecureRandom.hex(4)}@example.com",
      password: 'Test123!@',
      password_confirmation: 'Test123!@',
      confirmed_at: Time.current
    )
  end

  def create_token(scopes: 'labels.read')
    described_class.create!(owner: user, name: "tk-#{SecureRandom.hex(3)}", scopes: scopes)
  end

  describe "storage" do
    def stored(id)
      described_class.connection.select_value("SELECT token FROM access_tokens WHERE id = '#{id}'")
    end

    it "stores the hash of the generated value, never the value" do
      token = create_token

      expect(token.token).to match(/\A\h{64}\z/)
      expect(stored(token.id)).to eq(Digest::SHA256.hexdigest(token.token))
    end

    it "has only the hash once read back" do
      token = create_token

      expect(described_class.find(token.id).token).to eq(Digest::SHA256.hexdigest(token.token))
    end

    it "finds a token by its raw value" do
      token = create_token

      expect(described_class.for_token(token.token)).to eq(token)
      expect(described_class.for_token("not-a-token")).to be_nil
      expect(described_class.for_token(nil)).to be_nil
    end

    it "finds a token stored before hashing by its value and hashes it" do
      raw = SecureRandom.hex(32)
      id = SecureRandom.uuid
      described_class.connection.execute(<<~SQL.squish)
        INSERT INTO access_tokens (id, name, owner_type, owner_id, scopes, token, created_at, updated_at)
        VALUES ('#{id}', 'legacy', 'User', '#{user.id}', 'labels.read', '#{raw}', now(), now())
      SQL

      expect(described_class.for_token(raw)&.id).to eq(id)
      expect(stored(id)).to eq(Digest::SHA256.hexdigest(raw))
      expect(described_class.for_token(raw)&.id).to eq(id)
    end
  end

  describe '#update_token' do
    it 'replaces the value and drops the cached validation of the old one' do
      token = create_token
      old_value = token.token
      allow(TokenValidationService).to receive(:invalidate_cache_for_digest)

      token.update_token

      expect(token.token).not_to eq(old_value)
      expect(described_class.for_token(old_value)).to be_nil
      expect(described_class.for_token(token.token)).to eq(token)
      expect(TokenValidationService).to have_received(:invalidate_cache_for_digest)
        .with(Digest::SHA256.hexdigest(old_value))
    end
  end

  describe '#has_scope?' do
    it 'allows only the listed scopes, the basic reads and what the scopes imply' do
      token = create_token(scopes: 'conversations.read,labels.create')

      expect(token.has_scope?('conversations.read')).to be(true)
      expect(token.has_scope?('labels.create')).to be(true)
      expect(token.has_scope?('labels.write')).to be(true)
      expect(token.has_scope?('inboxes.read')).to be(true)
      expect(token.has_scope?('dashboard.read')).to be(true)
      expect(token.has_scope?('contacts.read')).to be(false)
      expect(token.has_scope?('access_tokens.create')).to be(false)
    end

    it 'leaves a default-scoped token bounded by its owner only' do
      token = create_token(scopes: 'default')

      expect(token).to be_unrestricted
      expect(token.has_scope?('contacts.read')).to be(true)
      expect(token.effective_scopes).to eq([])
    end
  end
end
