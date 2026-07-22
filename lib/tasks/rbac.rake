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

  desc 'Re-seed account_owner permissions idempotently (run after deploying EVO-1061)'
  task reseed_account_owner: :environment do
    puts "🔄 Re-seeding account_owner permissions..."
    load Rails.root.join('db', 'seeds', 'rbac.rb')
    puts "✅ Done."
  end

  desc 'Reconcile the super_admin role with the full permission catalog (idempotent, safe on every boot)'
  task reconcile_super_admin: :environment do
    result = RbacGrantReconciler.reconcile!

    if result[:role].nil?
      puts "ℹ️  super_admin role not found (installation not bootstrapped yet) — nothing to reconcile."
    elsif result[:added].zero? && result[:removed].zero?
      puts "✅ super_admin already holds the full catalog (#{RbacGrantReconciler.catalog_keys.size} permissions)."
    else
      puts "🔄 super_admin reconciled: +#{result[:added]} granted, -#{result[:removed]} stale removed " \
           "(catalog: #{RbacGrantReconciler.catalog_keys.size})."
    end
  end

  desc 'Check (without writing) whether the super_admin grant set diverged from the catalog; exits non-zero on drift'
  task check_super_admin_drift: :environment do
    if RbacGrantReconciler.role.nil?
      puts "ℹ️  super_admin role not found (installation not bootstrapped yet)."
      next
    end

    missing = RbacGrantReconciler.missing_keys
    stale = RbacGrantReconciler.stale_keys

    if missing.empty? && stale.empty?
      puts "✅ No drift: super_admin holds exactly the catalog (#{RbacGrantReconciler.catalog_keys.size} permissions)."
      next
    end

    puts "❌ super_admin grant drift detected:"
    puts "   Missing (#{missing.size}): #{missing.join(', ')}" if missing.any?
    puts "   Stale (#{stale.size}): #{stale.join(', ')}" if stale.any?
    puts "💡 Run `rails rbac:reconcile_super_admin` to converge."
    abort
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