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
      avatar_url: user.avatar_url,
      created_at: user.created_at,
      updated_at: user.updated_at,
      ui_settings: user.ui_settings || {},
      mfa_enabled: user.mfa_enabled?,
      mfa_setup_incomplete: user.mfa_setup_incomplete?,
      display_name: user.display_name,
      available_name: user.available_name,
      availability: user.availability,
      confirmed: user.confirmed?,
      confirmed_at: user.confirmed_at,
      custom_attributes: user.custom_attributes || {},
      setup_survey_completed: user.setup_survey_completed?
    }

    # Optional fields
    base_data[:last_sign_in_at] = user.last_sign_in_at if options[:include_sign_in]
    base_data[:sign_in_count] = user.sign_in_count if options[:include_sign_in]

    base_data
  end

  # Directory variant for lists of OTHER users (CRM-535). Never carries
  # pubsub_token: with it plus the id anyone can subscribe to that user's
  # RoomChannel stream. ui_settings, custom_attributes and MFA state are the
  # user's own too. `full` stays for payloads whose reader is the user itself.
  def directory(user)
    return nil unless user

    {
      id: user.id,
      name: user.name,
      email: user.email,
      type: user.type,
      role: user.role_data,
      avatar_url: user.avatar_url,
      display_name: user.display_name,
      available_name: user.available_name,
      availability: user.availability,
      confirmed: user.confirmed?,
      confirmed_at: user.confirmed_at,
      created_at: user.created_at,
      updated_at: user.updated_at
    }
  end

  # `full` when the reader is the user itself, `directory` otherwise.
  def for_reader(user, reader)
    return nil unless user

    reader && user.id == reader.id ? full(user) : directory(user)
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
