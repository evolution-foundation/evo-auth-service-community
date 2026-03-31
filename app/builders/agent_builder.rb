# The AgentBuilder class is responsible for creating a new agent (user) and assigning their role.
class AgentBuilder
  pattr_initialize [:email, :password, { name: '' }, :inviter, { role: :agent }, { availability: :offline }]

  # Creates a user and assigns their role in a transaction.
  # @return [User] the created or found user.
  def perform
    ActiveRecord::Base.transaction do
      @user = find_or_create_user
      assign_role
    end
    @user
  end

  private

  def find_or_create_user
    user = User.from_email(email)
    return user if user

    generated_password = password.presence || "1!aA#{SecureRandom.alphanumeric(12)}"
    User.create!(email: email, name: name, password: generated_password)
  end

  def assign_role
    system_role = Role.find_by!(key: role)

    existing = @user.user_roles.joins(:role).where(roles: { system: false })
    existing.destroy_all if existing.exists?

    UserRole.assign_role_to_user(@user, system_role, inviter)
  end
end
