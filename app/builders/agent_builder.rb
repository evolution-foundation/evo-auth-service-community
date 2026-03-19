# The AgentBuilder class is responsible for creating a new agent.
# It initializes with necessary attributes and provides a perform method
# to create a user and account user in a transaction.
class AgentBuilder
  # Initializes an AgentBuilder with necessary attributes.
  # @param email [String] the email of the user.
  # @param name [String] the name of the user.
  # @param role [String] the role of the user, defaults to 'agent' if not provided.
  # @param inviter [User] the user who is inviting the agent (Current.user in most cases).
  # @param availability [String] the availability status of the user, defaults to 'offline' if not provided.
  # @param auto_offline [Boolean] the auto offline status of the user.
  # @param password [String] the password of the user

  pattr_initialize [:email, :password, { name: '' }, :inviter, :account, { role: :agent }, { availability: :offline }, { auto_offline: false }]

  # Creates a user and account user in a transaction.
  # @return [User] the created user.
  def perform
    ActiveRecord::Base.transaction do
      @user = find_or_create_user
      create_account_user
    end
    @user
  end

  private

  # Finds a user by email or creates a new one with a temporary password.
  # @return [User] the found or created user.
  def find_or_create_user
    user = User.from_email(email)
    return user if user

    if !password.present?
      password = "1!aA#{SecureRandom.alphanumeric(12)}"
    end

    User.create!(email: email, name: name, password: password)
    
  end

  # Checks if the user needs confirmation.
  # @return [Boolean] true if the user is persisted and not confirmed, false otherwise.
  def user_needs_confirmation?
    @user.persisted? && !@user.confirmed?
  end

  # Creates an account user linking the user to the current account.
  def create_account_user
    # Try to find custom role first, then system role
    custom_role = account.account_custom_roles.find_by(key: role)
    system_role = Role.find_by(key: role) unless custom_role

    if custom_role.nil? && system_role.nil?
      Rails.logger.error "Role '#{role}' not found. Available system roles: #{Role.pluck(:key)}, Available custom roles: #{account.account_custom_roles.pluck(:key)}"
      raise ActiveRecord::RecordNotFound, "Role '#{role}' not found"
    end

    if custom_role
      Rails.logger.info "Creating AccountUser with custom_role_id: #{custom_role.id} (role key: #{custom_role.key})"

      # Create AccountUser with account_custom_role_id (custom role)
      account_user = AccountUser.create!({
        account_id: account.id,
        user_id: @user.id,
        account_custom_role_id: custom_role.id,
        inviter_id: inviter.id,
      }.merge({
        availability: availability,
        auto_offline: auto_offline
      }.compact))
    else
      Rails.logger.info "Creating AccountUser with role_id: #{system_role.id} (role key: #{system_role.key})"

      # Create AccountUser with role_id (system role)
      account_user = AccountUser.create!({
        account_id: account.id,
        user_id: @user.id,
        role_id: system_role.id,
        inviter_id: inviter.id,
      }.merge({
        availability: availability,
        auto_offline: auto_offline
      }.compact))

      # Remove any existing account roles before assigning the new one
      # This ensures we don't have multiple account roles for the same user
      existing_account_roles = @user.user_roles.joins(:role).where(roles: { system: false })
      existing_account_roles.destroy_all if existing_account_roles.exists?

      # Also assign role via user_roles table (user-level role) - only for system roles
      UserRole.assign_role_to_user(@user, system_role, inviter)
    end

    account_user
  end
end
