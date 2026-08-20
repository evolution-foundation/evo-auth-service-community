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

# Keys withheld from Account Owner (super_admin only). Every entry MUST exist
# in ResourceActionsConfig — keys absent from the catalog are inert here (the
# subtraction below can only remove keys the catalog produces) and just
# mislead readers; ~50 such phantom leftovers from removed enterprise
# resources (plans/features/audit_logs/...) were pruned.
account_owner_exclusive = [
  'accounts.stats',
  # Installation-level configuration (SMTP, Storage, Social Login, OpenAI,
  # Channels, Inbound Email, Frontend Runtime). Reserved for the
  # super_admin role — the bootstrap user gets it and it is the only role
  # that may render the "Admin Settings" panel and call /api/v1/installation_configs/**.
  'installation_configs.manage'
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
  # Operational reads previously inherited via BASIC_READ_PERMISSIONS. Now that
  # the split removed users.read/inboxes.read from BASIC, the agent role grants
  # them explicitly. The agent is SECURE-BY-DEFAULT for inbox visibility: it does
  # NOT get conversations.read_all, so it sees only the inboxes it is a member of
  # (User#assigned_inboxes) — an agent with no membership sees nothing until it is
  # assigned. account_owner/super_admin still see everything (read_all grant +
  # administrator?). NOTE: users.manage is intentionally NOT granted — agents do
  # not see the administrative panel.
  'users.read',
  'conversations.read', 'conversations.create', 'conversations.update',
  'conversations.meta', 'conversations.search', 'conversations.filter', 'conversations.available_for_pipeline',
  'conversations.mute', 'conversations.unmute', 'conversations.transcript', 'conversations.toggle_status',
  'conversations.toggle_priority', 'conversations.toggle_typing_status', 'conversations.update_last_seen',
  'conversations.unread', 'conversations.custom_attributes', 'conversations.attachments', 'conversations.inbox_assistant',
  'conversations.import',
  'contacts.read', 'contacts.create', 'contacts.update',
  'contacts.active', 'contacts.search', 'contacts.filter', 'contacts.import', 'contacts.export',
  'contacts.contactable_inboxes', 'contacts.destroy_custom_attributes', 'contacts.avatar',
  # CRM-166: the agent writes attribute VALUES but had no read on the definitions,
  # so GET /custom_attribute_definitions 403'd and read-only screens rendered "no
  # attributes". Read only: create/update/delete stay administrative, and the CRM Settings
  # screen is gated on those, not on this key.
  'custom_attribute_definitions.read',
  'pipelines.read',
  # Card writes gate on pipeline_items.update (its own key), NOT pipelines.update —
  # the agent moves/creates cards without the manager's power to reshape/archive the
  # funnel. See PipelineItemsController + PipelinePolicy#update_items? in the CRM (CRM-178).
  'pipeline_items.update',
  # pipeline_stages.delete is NOT granted: deleting a funnel stage is a destructive
  # restructuring of the shared pipeline, not attendance. Create/update stay for the
  # kanban experience.
  'pipeline_stages.read', 'pipeline_stages.create', 'pipeline_stages.update',
  # accounts.update is administrative (Settings > Account) and deliberately
  # NOT granted; PATCH /api/v1/account enforces it.
  'accounts.read',
  'profiles.read', 'profiles.update', 'profiles.update_avatar', 'profiles.update_password', 'profiles.manage_notifications',
  # Operational resources used inside conversations. Product decision (CRM-70,
  # 2026-08-18): the agent MANAGES its own labels and canned responses, so those
  # keep read/create/update. Macros and message templates are use-vs-manage:
  # the agent keeps `read` (send a template) and `macros.execute` (run one) for
  # the chat, while `create`/`update` and the Settings screen belong to
  # `<resource>.manage`, granted to admin roles only. Deletes of every shared
  # asset stay out (CRM-190). Personal macros an agent already owns keep working.
  'labels.read', 'labels.create', 'labels.update',
  'canned_responses.read', 'canned_responses.create', 'canned_responses.update',
  'message_templates.read',
  'macros.read', 'macros.execute',
  # teams powers the in-chat "Assign team" picker (GET /teams), so the read is
  # operational and kept here (also in BASIC_READ_PERMISSIONS). Create/update/delete
  # are NOT granted: creating, renaming and deleting teams — and managing members via
  # team_members, gated by teams.update — is a manager/settings action, not attendance.
  # The Settings screen itself is gated by teams.manage (CRM-70), which the agent
  # does not hold: read alone cannot hide it, since teams.read is basic for everyone.
  'teams.read',
  'inboxes.read'
  # EVO-1938: administrative Settings resources (AI Agents/Bots/API keys/folders/
  # sessions, Integrations, Channels, Working Hours, Segments, Journeys, Campaigns)
  # are intentionally NOT granted to the default agent. The frontend routes/menu and
  # the CRM controllers gate by these keys, so omitting them hides the screens and
  # 403s the endpoints.
]

agent.role_permissions_actions.destroy_all
agent_permissions.select { |key| ResourceActionsConfig.valid_permission?(key) }.each do |permission_key|
  agent.role_permissions_actions.create!(permission_key: permission_key)
end
puts "   📋 Assigned #{agent_permissions.select { |key| ResourceActionsConfig.valid_permission?(key) }.size} permissions to #{agent.name}"

# Super Admin (installation-level operator)
# In the Community edition there is exactly one user with this role: the
# user created via the setup wizard (bootstrap). They keep everything an
# Account Owner has, plus the installation-level configuration permissions
# that no other role should ever hold (SMTP, Storage, Social Login, OpenAI,
# Frontend Runtime, etc.).
super_admin = Role.find_or_initialize_by(key: 'super_admin')
if super_admin.new_record?
  super_admin.name = 'Super Admin'
  super_admin.description = 'Installation owner — full account access plus installation-level configuration'
  super_admin.system = true
  super_admin.type = 'user'
  super_admin.save!
  puts "   ✅ Created role: #{super_admin.name}"
else
  puts "   ♻️ Role already exists: #{super_admin.name}"
end

super_admin_permissions = ResourceActionsConfig.all_permission_keys.select do |key|
  ResourceActionsConfig.valid_permission?(key)
end

super_admin.role_permissions_actions.destroy_all
super_admin_permissions.each do |permission_key|
  super_admin.role_permissions_actions.create!(permission_key: permission_key)
end
puts "   📋 Assigned #{super_admin_permissions.size} permissions to #{super_admin.name}"

puts "✅ RBAC seeds created successfully!"