# frozen_string_literal: true

namespace :rbac do
  desc 'Display ResourceActionsConfig information'
  task show_config: :environment do
    puts "🔄 ResourceActionsConfig Information"
    puts "=" * 50
    
    puts "📋 Available resources:"
    ResourceActionsConfig.all_resources.each do |key, config|
      action_count = config[:actions].size
      puts "   #{config[:name]} (#{key}): #{action_count} actions"
    end
    
    puts "\n📊 Summary:"
    puts "   Total Resources: #{ResourceActionsConfig.all_resources.size}"
    puts "   Total Permissions: #{ResourceActionsConfig.all_permission_keys.size}"
  end

  desc 'List all configured permissions'
  task list_permissions: :environment do
    puts "📋 All configured permissions:"
    puts
    
    ResourceActionsConfig.all_resources.each do |resource_key, resource_config|
      puts "#{resource_config[:name]} (#{resource_key}):"
      resource_config[:actions].each do |action_key, action_config|
        permission_key = "#{resource_key}.#{action_key}"
        puts "  ├─ #{permission_key} - #{action_config[:name]}"
      end
      puts
    end
    
    puts "Total: #{ResourceActionsConfig.all_permission_keys.size} permissions"
  end

  desc 'Validate configuration integrity'
  task validate: :environment do
    puts "🔍 Validating ResourceActionsConfig integrity..."
    
    # Check permission keys used in database
    used_permission_keys = RolePermissionsAction.distinct.pluck(:permission_key)
    config_permission_keys = ResourceActionsConfig.all_permission_keys
    
    puts "✅ Validation Results:"
    puts "   Configured Permissions: #{config_permission_keys.size}"
    puts "   Used in Database: #{used_permission_keys.size}"
    puts
    
    # Find invalid permissions in database
    invalid_permissions = used_permission_keys - config_permission_keys
    
    if invalid_permissions.any?
      puts "❌ Invalid permissions in database (not in config):"
      invalid_permissions.each { |key| puts "   - #{key}" }
      puts
    end
    
    # Find unused permissions
    unused_permissions = config_permission_keys - used_permission_keys
    
    if unused_permissions.any?
      puts "⚠️  Configured but unused permissions:"
      unused_permissions.each { |key| puts "   - #{key}" }
      puts
    end
    
    if invalid_permissions.empty? && unused_permissions.empty?
      puts "✅ All permissions are valid and used!"
    else
      puts "💡 Consider reviewing permission usage and configuration"
    end
  end
end