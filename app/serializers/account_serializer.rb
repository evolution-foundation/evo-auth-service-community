# frozen_string_literal: true

module AccountSerializer
  extend self

  # Full account serialization with all details
  def full(account, options = {})
    return nil unless account

    timings = options[:_timings] || {}
    serializer_start = Time.current

    data = {
      id: account.id,
      name: account.name,
      domain: account.domain,
      support_email: account.support_email,
      locale: account.locale,
      status: account.status,
      created_at: account.created_at,
      updated_at: account.updated_at
    }

    # Optional fields
    data[:settings] = account.settings if options[:include_settings]
    data[:custom_attributes] = account.custom_attributes if options[:include_attributes]

    if options[:include_role]
      role_start = Time.current
      # Use preloaded account_user if available
      data[:role] = if options[:account_user]
                      options[:account_user].role_data
      else
                      account.role_data  # Fallback (still queries)
      end
      timings[:role_data] = (Time.current - role_start) * 1000
    end

    if options[:include_counts]
      data[:conversations_count] = account.try(:conversations_count) || 0
      data[:inboxes_count] = account.try(:inboxes_count) || 0
      data[:users_count] = account.try(:users_count) || 0
      data[:contacts_count] = account.try(:contacts_count) || 0
    end

    timings[:other] = ((Time.current - serializer_start) * 1000) - (timings[:role_data] || 0)

    data
  end

  # Basic account serialization
  def basic(account)
    return nil unless account

    {
      id: account.id,
      name: account.name,
      status: account.status
    }
  end

  # Account with role for specific user
  def with_role(account, user: nil)
    return nil unless account

    data = {
      id: account.id,
      name: account.name,
      status: account.status,
      domain: account.domain,
      locale: account.locale
    }

    if user
      account_user = user.account_users.find_by(account: account)
      data[:role] = account_user&.role_data
    end

    data
  end

  # For super admin account management
  def for_admin(account)
    return nil unless account

    {
      id: account.id,
      name: account.name,
      domain: account.domain,
      status: account.status,
      locale: account.locale,
      created_at: account.created_at,
      updated_at: account.updated_at,
      users_count: account.account_users.count,
      settings: account.settings,
      custom_attributes: account.custom_attributes,
      role: account.role_data
    }
  end
end
