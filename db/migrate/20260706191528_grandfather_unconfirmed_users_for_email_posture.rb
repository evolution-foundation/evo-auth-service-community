# Story 8.3b (EVO-2016): the login barrier now keys on confirmation_sent_at
# ("did this account ever get a confirmation email?"). Devise stamps that
# column at create even when no email is sent, so every pre-existing
# unconfirmed account carries it and would be locked out retroactively once
# the posture derives to required (SMTP configured). Clear it for accounts
# that never confirmed and have no pending email change — from here on the
# signup flow only leaves confirmation_sent_at set when an email actually
# went out.
class GrandfatherUnconfirmedUsersForEmailPosture < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL
      UPDATE users
      SET confirmation_sent_at = NULL
      WHERE confirmed_at IS NULL
        AND unconfirmed_email IS NULL
    SQL
  end

  def down
    # Data amnesty; nothing meaningful to restore.
  end
end
