# frozen_string_literal: true

require 'rails_helper'

# Regression spec for EVO-991.
# Covers backup-code generation (BCrypt hashing) and single-use consumption.
RSpec.describe TwoFactorAuthenticatable, type: :model do
  let(:user) do
    User.create!(
      name: 'Test User',
      email: "two-factor-spec-#{SecureRandom.hex(4)}@example.com",
      password: 'Test123!@',
      password_confirmation: 'Test123!@',
      confirmed_at: Time.current,
      otp_required_for_login: true,
      mfa_method: :totp
    )
  end

  describe '#generate_otp_backup_codes!' do
    subject(:plaintext_codes) { user.generate_otp_backup_codes! }

    it 'returns 10 plaintext codes' do
      expect(plaintext_codes.length).to eq(10)
    end

    it 'returns 8-character alphanumeric codes' do
      expect(plaintext_codes).to all(match(/\A[A-Z0-9]{8}\z/))
    end

    it 'stores BCrypt hashes in the DB, not plaintext' do
      plaintext_codes
      user.reload
      expect(user.otp_backup_codes).to all(start_with('$2a$'))
    end

    it 'invalidates the previous set of codes when regenerated' do
      first_plaintext = user.generate_otp_backup_codes!
      user.generate_otp_backup_codes!
      user.reload

      first_plaintext.each do |code|
        expect(user.check_backup_code(code)).to be(false)
      end
    end
  end

  describe '#check_backup_code' do
    let!(:plaintext_codes) { user.generate_otp_backup_codes! }
    let(:valid_code) { plaintext_codes.first }

    it 'returns true for a valid backup code' do
      expect(user.check_backup_code(valid_code)).to be(true)
    end

    it 'consumes the code so it cannot be used again' do
      user.check_backup_code(valid_code)
      expect(user.check_backup_code(valid_code)).to be(false)
    end

    it 'reduces the remaining codes count by one after use' do
      expect { user.check_backup_code(valid_code) }
        .to change { user.reload.otp_backup_codes.length }.from(10).to(9)
    end

    it 'returns false for an invalid code' do
      expect(user.check_backup_code('INVALID1')).to be(false)
    end

    it 'returns false when there are no codes' do
      User.where(id: user.id).update_all(otp_backup_codes: [])
      user.reload
      expect(user.check_backup_code(valid_code)).to be(false)
    end

    it 'accepts the code case-insensitively' do
      expect(user.check_backup_code(valid_code.downcase)).to be(true)
    end
  end
end
