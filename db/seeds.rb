# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.

puts "🌱 Seeding Evo Auth Service (Community)..."

# Seed RBAC system first
puts "📋 Seeding RBAC system..."
require_relative 'seeds/rbac'
puts "✅ Seeded RBAC system with roles, actions and permissions"

# Create default account
default_account = Account.find_or_create_by!(name: 'Evolution Community') do |account|
  account.domain = "localhost"
  account.support_email = "support@evo-auth-service-community.com"
  account.locale = :en
  account.status = :active
  account.settings = {}
  account.custom_attributes = {}
  account.internal_attributes = {}
end

# Create user
user = User.find_or_create_by!(email: "support@evo-auth-service-community.com") do |user|
  user.name = "User"
  user.password = "Password@123"
  user.password_confirmation = "Password@123"
  user.provider = "email"
  user.uid = "support@evo-auth-service-community.com"
  user.availability = :online
  user.mfa_method = :disabled
  user.confirmed_at = Time.current
  user.type = "User"
end

# Ensure password is up to date with Argon2 hash
if user.persisted? && !user.new_record?
  user.password = "Password@123"
  user.password_confirmation = "Password@123"
  user.save!
end

# Create account user relationship
user_role = Role.find_by(key: 'account_owner')
AccountUser.find_or_create_by!(
  account: default_account,
  user: user
) do |au|
  au.role_id = user_role&.id
  au.availability = :online
  au.auto_offline = true
end

# Assign RBAC role to user
account_owner_role = Role.find_by(key: 'account_owner')
if account_owner_role && !user.has_role?('account_owner')
  UserRole.assign_role_to_user(user, account_owner_role)
  puts "✅ Assigned account_owner role to user"
end

# Migrate existing AccountUser roles to RBAC system
puts "🔄 Migrating existing roles to RBAC system..."
migrated_count = 0

AccountUser.includes(:user, :account).find_each do |account_user|
  account = account_user.account
  user = account_user.user
  
  # Skip if already has RBAC roles
  begin
    has_roles = user.user_roles.where(user: user).exists?
    next if has_roles
  rescue => e
    puts "⚠️ Erro ao verificar roles para Users #{account_user.id}: #{e.message}"
    next
  end
  
  # Encontrar a role global por key
  role = Role.find_by(key: account_user.role)
  
  if role
    UserRole.find_or_create_by(
      user: user,
      role: role,
      account: account
    ) do |user_role|
      user_role.granted_at = account_user.created_at
      user_role.granted_by = nil # No granted_by for migrated roles
      user_role.save!
    end
    
    migrated_count += 1
  end
end

# Create default OAuth application
oauth_app = OauthApplication.find_or_create_by!(name: "Default OAuth App") do |app|
  app.account = default_account
  app.uid = SecureRandom.uuid
  app.secret = Doorkeeper::OAuth::Helpers::UniqueToken.generate
  app.redirect_uri = "http://localhost:5173/oauth/callback"
  app.scopes = "read write admin"
  app.confidential = false
  app.trusted = true
end
puts "✅ Seeded #{OauthApplication.count} oauth applications"
puts "   Client ID: #{oauth_app.uid}"
puts "   Client Secret: #{oauth_app.secret}"

# Create access token for user
access_token = user.create_token
puts "✅ Seeded #{AccessToken.count} access tokens"
puts "   Token: #{access_token.token}"

puts ""
puts "🎉 Seeding completed successfully!"
puts ""
puts "📋 Summary:"
puts "   - Account: #{default_account.name} (ID: #{default_account.id})"
puts "   - user: #{user.email}"
puts "   - OAuth App: #{oauth_app.name}"
puts "   - Client ID: #{oauth_app.uid}"
puts "   - Access Token: #{access_token.token}"
puts "   - Roles: #{Role.count}"
puts "   - Role Permission Actions: #{RolePermissionsAction.count}"
puts ""
puts "🚀 You can now start using the Evo Auth Service!"
