# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AgentBuilder do
  let!(:agent_role) do
    Role.find_by(key: 'agent') || Role.create!(key: 'agent', name: 'Agent', type: 'user')
  end
  let(:inviter) do
    User.create!(email: 'admin@example.com', name: 'Admin', password: 'Adm1n!Pass')
  end

  describe '#perform' do
    it 'creates a new user with confirmed_at already set so login works without email confirmation' do
      user = described_class.new(email: 'newagent@example.com', inviter: inviter).perform

      expect(user).to be_persisted
      expect(user.confirmed_at).to be_present
    end

    it 'assigns the default agent role when no role is passed' do
      user = described_class.new(email: 'agent1@example.com', inviter: inviter).perform

      expect(user.roles.map(&:key)).to include('agent')
    end

    context 'when the requested role key does not exist' do
      it 'falls back to the agent role instead of raising 500' do
        user = described_class.new(email: 'fallback@example.com', role: :nonexistent, inviter: inviter).perform

        expect(user.roles.map(&:key)).to include('agent')
      end
    end

    context 'when neither the requested role nor the agent fallback exists' do
      before do
        allow(Role).to receive(:find_by).and_return(nil)
        allow(Role).to receive(:find_by!).and_raise(ActiveRecord::RecordNotFound)
      end

      it 'raises RecordNotFound with a clear signal' do
        expect do
          described_class.new(email: 'broken@example.com', role: :nonexistent, inviter: inviter).perform
        end.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    it 'returns the existing user without recreating when email already registered' do
      existing = User.create!(email: 'exists@example.com', name: 'Exists', password: 'Ex1st!Pass')

      user = described_class.new(email: 'exists@example.com', inviter: inviter).perform

      expect(user.id).to eq(existing.id)
    end
  end
end
