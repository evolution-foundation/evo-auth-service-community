# frozen_string_literal: true

class InvalidatePlaintextBackupCodes < ActiveRecord::Migration[7.1]
  def up
    # Users who set up TOTP before EVO-991 (PR #16) have plaintext backup codes.
    # Those codes are silently ignored by check_backup_code's BCrypt filter,
    # leaving them locked out if they lose their TOTP device.
    # Zeroing the array + clearing mfa_confirmed_at forces them to regenerate
    # on their next MFA setup visit.
    #
    # DEPLOY NOTE: this UPDATE acquires row-level locks on all affected rows for
    # the duration of the transaction. On large deployments run during low-traffic
    # hours to avoid blocking concurrent login attempts.
    say_with_time 'Invalidating plaintext backup codes (EVO-1104)' do
      # otp_backup_codes is a native PostgreSQL text[] column, so we use
      # unnest() to iterate elements — not jsonb functions.
      result = execute <<~SQL
        WITH affected AS (
          SELECT id
          FROM users
          WHERE array_length(otp_backup_codes, 1) IS NOT NULL
            AND EXISTS (
              SELECT 1
              FROM unnest(otp_backup_codes) AS code
              WHERE code NOT LIKE '$2a$%'
                AND code NOT LIKE '$2b$%'
                AND code NOT LIKE '$2y$%'
            )
        )
        UPDATE users
        SET otp_backup_codes = '{}',
            mfa_confirmed_at  = NULL
        FROM affected
        WHERE users.id = affected.id
      SQL
      result.cmd_tuples
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
