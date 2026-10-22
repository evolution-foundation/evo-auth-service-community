# The AgentBuilder class is responsible for creating a new agent (user) and assigning their role.
class AgentBuilder
  pattr_initialize [:email, :password, { name: '' }, :inviter, { role: :agent }, { availability: :offline },
                    { reassign_existing: true }]

  # Creates a user and assigns their role in a transaction. An email already
  # registered keeps its roles unless `reassign_existing`, and only gets one when
  # it holds none — a caller with no user behind it (service token) resolves the
  # identity, it does not promote it.
  # @return [User] the created or found user.
  def perform
    ActiveRecord::Base.transaction do
      @user, created = find_or_create_user
      assign_role if created || reassign_existing || @user.roles.none?
    end
    @user
  end

  private

  def find_or_create_user
    user = User.from_email(email)
    return [user, false] if user

    generated_password = password.presence || "1!aA#{SecureRandom.alphanumeric(12)}"
    user = User.new(email: email, name: name, password: generated_password)
    user.skip_confirmation!
    user.save!
    [user, true]
  end

  def assign_role
    system_role = Role.find_by(key: role) || Role.find_by!(key: :agent)

    existing = @user.user_roles.joins(:role).where(roles: { system: false })
    existing.destroy_all if existing.exists?

    UserRole.assign_role_to_user(@user, system_role, inviter)
  end
end
