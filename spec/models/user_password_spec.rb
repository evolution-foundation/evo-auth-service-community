# frozen_string_literal: true

require 'rails_helper'

RSpec.describe User, type: :model do
  describe '#password_complexity' do
    let(:base_attrs) { { email: 'test@example.com', name: 'Test User' } }

    subject(:user) { User.new(base_attrs.merge(password: password)) }

    context 'when password is missing a special character' do
      let(:password) { 'NoSpecial1Abc' }

      it 'adds :missing_special_char error code' do
        user.valid?
        error = user.errors.where(:password).find { |e| e.type == :missing_special_char }
        expect(error).to be_present
      end
    end

    context 'when password is missing an uppercase letter' do
      let(:password) { 'nouppercase1!' }

      it 'adds :missing_uppercase error code' do
        user.valid?
        error = user.errors.where(:password).find { |e| e.type == :missing_uppercase }
        expect(error).to be_present
      end
    end

    context 'when password is missing a lowercase letter' do
      let(:password) { 'NOLOWER1!' }

      it 'adds :missing_lowercase error code' do
        user.valid?
        error = user.errors.where(:password).find { |e| e.type == :missing_lowercase }
        expect(error).to be_present
      end
    end

    context 'when password is missing a number' do
      let(:password) { 'NoNumbers!Ab' }

      it 'adds :missing_number error code' do
        user.valid?
        error = user.errors.where(:password).find { |e| e.type == :missing_number }
        expect(error).to be_present
      end
    end

    context 'when password meets all complexity requirements' do
      let(:password) { 'Valid1!Pass' }

      it 'has no complexity error codes' do
        user.valid?
        complexity_types = %i[missing_lowercase missing_uppercase missing_number missing_special_char]
        complexity_errors = user.errors.where(:password).select { |e| complexity_types.include?(e.type) }
        expect(complexity_errors).to be_empty
      end
    end
  end
end
