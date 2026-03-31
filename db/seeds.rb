# This file seeds RBAC roles and permissions required by the application.
# User, account, and OAuth app creation is handled by the Setup Wizard (POST /setup/bootstrap).

puts "🌱 Seeding Evo Auth Service (Community)..."

# Seed RBAC system
puts "📋 Seeding RBAC system..."
require_relative 'seeds/rbac'
puts "✅ Seeded RBAC system with roles, actions and permissions"
puts "   - Roles: #{Role.count}"
puts "   - Role Permission Actions: #{RolePermissionsAction.count}"

puts ""
puts "🚀 Run the setup wizard at /setup to create the first admin user."
