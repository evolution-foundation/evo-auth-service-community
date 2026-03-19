# frozen_string_literal: true

module AccountUserSerializer
  extend self

  def full(account_user)
    return nil unless account_user

    {
      id: account_user.id,
      user_id: account_user.user_id,
      account_id: account_user.account_id,
      account_name: account_user.account.name,
      role: account_user.role_data,
      availability: account_user.availability,
      active_at: account_user.active_at,
      created_at: account_user.created_at,
      updated_at: account_user.updated_at
    }
  end

  def with_user(account_user)
    return nil unless account_user

    data = full(account_user)
    data[:user] = UserSerializer.basic(account_user.user)
    data
  end
end
