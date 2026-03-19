# Seeds for RBAC using ResourceActionsConfig
puts "🔄 Creating default RBAC configuration..."

puts "📋 Verifying ResourceActionsConfig..."
total_permissions = ResourceActionsConfig.all_permission_keys.size
puts "   Available permissions: #{total_permissions}"

puts "🏷️ Creating default Roles..."

# Account Owner - Full access to account resources
account_owner = Role.find_or_initialize_by(key: 'account_owner')
if account_owner.new_record?
  account_owner.name = 'Account Owner'
  account_owner.description = 'Full access to account and all its resources'
  account_owner.system = true
  account_owner.type = 'user'
  account_owner.save!
  puts "   ✅ Created role: #{account_owner.name}"
else
  puts "   ♻️ Role already exists: #{account_owner.name}"
end

# Get all permissions except Account Owner specific ones
account_owner_exclusive = [
  'accounts.suspend',
  'accounts.activate',
  'accounts.seed',
  'accounts.reset_cache',
  'accounts.stats',
  'dashboard.view_admin',
  'dashboard.instance_status',
  'dashboard.system_info',
  'audit_logs.read',
  'audit_logs.export',
  'audit_logs.purge',
  'audit_logs.filter',
  'audit_logs.view_details',
  'plans.read',
  'plans.create',
  'plans.update',
  'plans.delete',
  'plans.assign',
  'plans.manage_features',
  'plans.activate_deactivate',
  'features.create',
  'features.update',
  'features.delete',
  'features.stats',
  'features.seed',
  'features.types',
  'roles.create',
  'roles.update',
  'roles.delete',
  'roles.stats',
  'roles.seed',
  'roles.add_permission',
  'roles.remove_permission',
  'roles.bulk_update_permissions',
  'account_features.read',
  'account_features.assign',
  'account_features.remove',
  'account_features.configure',
  'account_plans.read',
  'account_plans.assign',
  'account_plans.change',
  'plan_features.read',
  'plan_features.assign',
  'plan_features.remove',
  'plan_features.configure',
  'feature_types.read',
  'feature_types.create',
  'feature_types.update',
  'feature_types.delete',
  'resource_actions.sync',
  'permissions.create',
  'permissions.update',
  'permissions.delete',
  'permissions.assign',
  'permissions.bulk_operations'
]

account_owner_permissions = ResourceActionsConfig.all_permission_keys - account_owner_exclusive

# Filter out invalid permissions and log any issues
valid_permissions = account_owner_permissions.select { |key| ResourceActionsConfig.valid_permission?(key) }
invalid_permissions = account_owner_permissions - valid_permissions

if invalid_permissions.any?
  puts "   ⚠️ Warning: #{invalid_permissions.size} invalid permissions found: #{invalid_permissions.first(5).join(', ')}"
end

account_owner.role_permissions_actions.destroy_all
valid_permissions.each do |permission_key|
  account_owner.role_permissions_actions.create!(permission_key: permission_key)
end

puts "   📋 Assigned #{valid_permissions.size} permissions to #{account_owner.name}"
puts "   📊 Total available permissions: #{ResourceActionsConfig.all_permission_keys.size}"

# Agent (basic user)
agent = Role.find_or_initialize_by(key: 'agent')
if agent.new_record?
  agent.name = 'Agent'
  agent.description = 'Basic user with limited access'
  agent.system = true
  agent.type = 'account'
  agent.save!
  puts "   ✅ Created role: #{agent.name}"
else
  puts "   ♻️ Role already exists: #{agent.name}"
  # Atualizar o tipo da role existente se necessário
  if agent.type != 'account'
    agent.update!(type: 'account')
    puts "   🔄 Updated role type to 'account': #{agent.name}"
  end
end

agent_permissions = [
  'conversations.read', 'conversations.create', 'conversations.update', 'conversations.delete',
  'conversations.meta', 'conversations.search', 'conversations.filter', 'conversations.available_for_pipeline',
  'conversations.mute', 'conversations.unmute', 'conversations.transcript', 'conversations.toggle_status',
  'conversations.toggle_priority', 'conversations.toggle_typing_status', 'conversations.update_last_seen',
  'conversations.unread', 'conversations.custom_attributes', 'conversations.attachments', 'conversations.inbox_assistant',
  'contacts.read', 'contacts.create', 'contacts.update', 'contacts.delete',
  'contacts.active', 'contacts.search', 'contacts.filter', 'contacts.import', 'contacts.export',
  'contacts.contactable_inboxes', 'contacts.destroy_custom_attributes', 'contacts.avatar',
  'oauth_pipelines.read', 'oauth_pipelines.create', 'oauth_pipelines.update', 'oauth_pipelines.delete',
  'oauth_pipeline_stages.read', 'oauth_pipeline_stages.create', 'oauth_pipeline_stages.update', 'oauth_pipeline_stages.delete',
  'pipeline_stages.read', 'pipeline_stages.create', 'pipeline_stages.update', 'pipeline_stages.delete',
  'agents.read', 'agents.create', 'agents.update', 'agents.delete',
  'oauth_agents.read', 'oauth_agents.create', 'oauth_agents.update', 'oauth_agents.delete',
  'agent_bots.read', 'agent_bots.create', 'agent_bots.update', 'agent_bots.delete', 'agent_bots.avatar',
  'agent_apikeys.read', 'agent_apikeys.create', 'agent_apikeys.update', 'agent_apikeys.delete',
  'agent_folders.read', 'agent_folders.create', 'agent_folders.update', 'agent_folders.delete',
  'agent_shared_folders.read', 'agent_shared_folders.create', 'agent_shared_folders.update', 'agent_shared_folders.delete',
  'ai_chat_sessions.read', 'ai_chat_sessions.create', 'ai_chat_sessions.update', 'ai_chat_sessions.delete',
  'accounts.read', 'accounts.update',
  'profiles.read', 'profiles.update', 'profiles.update_avatar', 'profiles.update_password', 'profiles.manage_notifications',
  'teams.read', 'teams.create', 'teams.update', 'teams.delete',
  'team_members.read', 'team_members.create', 'team_members.update', 'team_members.delete',
  'labels.read', 'labels.create', 'labels.update', 'labels.delete',
  'canned_responses.read', 'canned_responses.create', 'canned_responses.update', 'canned_responses.delete',
  'macros.read', 'macros.create', 'macros.update', 'macros.delete', 'macros.execute',
  'inboxes.read',
  'channels.read',
  'integrations.read',
  'working_hours.read', 'working_hours.create', 'working_hours.update', 'working_hours.delete'
]

agent.role_permissions_actions.destroy_all
agent_permissions.select { |key| ResourceActionsConfig.valid_permission?(key) }.each do |permission_key|
  agent.role_permissions_actions.create!(permission_key: permission_key)
end
puts "   📋 Assigned #{agent_permissions.select { |key| ResourceActionsConfig.valid_permission?(key) }.size} permissions to #{agent.name}"

puts "✅ RBAC seeds created successfully!"