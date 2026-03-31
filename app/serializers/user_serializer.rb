# frozen_string_literal: true

module UserSerializer
  extend self

  # Full user serialization with all details
  def full(user, options = {})
    return nil unless user

    base_data = {
      id: user.id,
      name: user.name,
      email: user.email,
      type: user.type,
      role: user.role_data,
      pubsub_token: user.pubsub_token,
      created_at: user.created_at,
      updated_at: user.updated_at,
      ui_settings: user.ui_settings || {},
      mfa_enabled: user.mfa_enabled?,
      display_name: user.display_name,
      available_name: user.available_name,
      availability: user.availability,
      confirmed: user.confirmed?,
      confirmed_at: user.confirmed_at,
      custom_attributes: user.custom_attributes || {}
    }

    # Optional fields
    base_data[:last_sign_in_at] = user.last_sign_in_at if options[:include_sign_in]
    base_data[:sign_in_count] = user.sign_in_count if options[:include_sign_in]

    base_data
  end

  # Safe serialization for list endpoints (excludes pubsub_token, custom_attributes, ui_settings, mfa)
  def list(user)
    return nil unless user

    {
      id: user.id,
      name: user.name,
      email: user.email,
      display_name: user.display_name,
      available_name: user.available_name,
      role: user.role_data,
      confirmed: user.confirmed?,
      confirmed_at: user.confirmed_at,
      availability: user.availability,
      type: user.type,
      created_at: user.created_at
    }
  end

  # Basic user serialization (for lists, references)
  def basic(user)
    return nil unless user

    {
      id: user.id,
      name: user.name,
      display_name: user.display_name,
      email: user.email,
      type: user.type,
      confirmed: user.confirmed?
    }
  end

  # Minimal user serialization (for tokens, auth responses)
  def minimal(user)
    return nil unless user

    {
      id: user.id,
      name: user.name,
      email: user.email,
      type: user.type
    }
  end

  # User with role information
  def with_role(user)
    return nil unless user

    data = basic(user)
    data[:role] = user.role_data
    data
  end

  # For super admin user management
  def for_admin(user)
    return nil unless user

    {
      id: user.id,
      name: user.name,
      display_name: user.display_name,
      email: user.email,
      type: user.type,
      role: user.role_data,
      confirmed: user.confirmed?,
      custom_attributes: user.custom_attributes,
      created_at: user.created_at,
      updated_at: user.updated_at,
      last_sign_in_at: user.last_sign_in_at,
      sign_in_count: user.sign_in_count
    }
  end
end
