# frozen_string_literal: true

require 'rails_helper'

# Regression spec for EVO-991 and EVO-1104.
# Covers backup-code generation (BCrypt hashing), single-use consumption,
# mixed legacy arrays (plaintext + BCrypt), and the mfa_setup_incomplete? predicate.
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

  describe '#mfa_setup_incomplete?' do
    it 'returns false when MFA is not required at all' do
      user.update_columns(otp_required_for_login: false, mfa_confirmed_at: nil)
      expect(user.mfa_setup_incomplete?).to be(false)
    end

    it 'returns true when MFA is required but not yet confirmed' do
      user.update_columns(otp_required_for_login: true, mfa_confirmed_at: nil)
      expect(user.mfa_setup_incomplete?).to be(true)
    end

    it 'returns false when MFA is fully configured' do
      user.update_columns(otp_required_for_login: true, mfa_confirmed_at: Time.current)
      expect(user.mfa_setup_incomplete?).to be(false)
    end
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
      expect(user.otp_backup_codes).to all(match(/\A\$2[aby]\$/))
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

    context 'with a mixed legacy array (plaintext + BCrypt)' do
      let(:legacy_plaintext) { 'LEGACY01' }

      before do
        mixed = [legacy_plaintext] + user.otp_backup_codes
        User.where(id: user.id).update_all(otp_backup_codes: mixed)
        user.reload
      end

      it 'silently ignores the plaintext entry and returns false for it' do
        expect(user.check_backup_code(legacy_plaintext)).to be(false)
      end

      it 'still validates a valid BCrypt-hashed code from the same array' do
        expect(user.check_backup_code(valid_code)).to be(true)
      end
    end

    it 'accepts the code case-insensitively' do
      expect(user.check_backup_code(valid_code.downcase)).to be(true)
    end

    context 'after migration invalidated plaintext codes (empty array, mfa_confirmed_at nil)' do
      before do
        User.where(id: user.id).update_all(otp_backup_codes: [], mfa_confirmed_at: nil)
        user.reload
      end

      it 'returns false and does not raise' do
        expect(user.check_backup_code(valid_code)).to be(false)
      end
    end
  end
end
