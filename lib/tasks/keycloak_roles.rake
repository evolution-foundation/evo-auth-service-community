namespace :keycloak do
  desc "Create Evolution roles from Keycloak role keys and seed them with agent permissions. " \
       "Usage: ROLES='supervisor,admin' ROLE_TYPE='user' rails keycloak:create_roles"
  task create_roles: :environment do
    role_keys = ENV['ROLES']&.split(',')&.map(&:strip)&.reject(&:blank?)

    if role_keys.blank?
      puts "Error: ROLES env var required. Example: ROLES='supervisor,admin' rails keycloak:create_roles"
      exit 1
    end

    role_type = ENV.fetch('ROLE_TYPE', 'user')
    unless %w[user account].include?(role_type)
      puts "Error: ROLE_TYPE must be 'user' or 'account'"
      exit 1
    end

    agent_permissions = Role.find_by(key: 'agent')&.role_permissions_actions&.pluck(:permission_key) || []
    if agent_permissions.empty?
      puts "Warning: agent role not found or has no permissions — roles will be created without permissions"
    else
      puts "Seeding with #{agent_permissions.size} permissions from agent role"
    end

    role_keys.each do |key|
      role = Role.find_or_initialize_by(key: key)
      if role.new_record?
        role.name        = key.split(/[_\-]/).map(&:capitalize).join(' ')
        role.type        = role_type
        role.system      = false
        role.description = "Imported from Keycloak"
        role.save!
        puts "Created: #{role.key} (type: #{role.type})"
      else
        puts "Already exists: #{role.key}"
      end

      if agent_permissions.any?
        existing = role.role_permissions_actions.pluck(:permission_key)
        missing  = agent_permissions - existing
        if missing.any?
          missing.each { |perm| role.role_permissions_actions.create!(permission_key: perm) }
          puts "  -> Added #{missing.size} missing permissions"
        else
          puts "  -> Permissions already up to date"
        end
      end
    end
  end
end