# frozen_string_literal: true

namespace :i18n do
  desc "Check for missing I18n translations"
  task check: :environment do
    puts "Checking I18n translations..."
    
    # List of all I18n.t calls found in the codebase
    translations_to_check = [
      'errors.signup.blocked_domain',
      'errors.signup.disposable_email',
      'errors.signup.invalid_email',
      'errors.signup.email_already_exists',
      'errors.signup.invalid_params',
      'errors.signup.failed',
      'errors.signup.user_not_found',
      'errors.plan_upgrade_required.failed',
      'devise_token_auth.passwords.missing_email',
      'devise_token_auth.passwords.user_not_found',
      'devise_token_auth.registrations.missing_confirm_success_url',
      'devise_token_auth.registrations.redirect_url_not_allowed',
      'devise_token_auth.registrations.email_already_exists'
    ]
    
    # Check all available locales
    locales = I18n.available_locales
    all_missing = {}
    
    locales.each do |locale|
      I18n.locale = locale
      puts "\n=== Checking locale: #{locale} ==="
      missing = []
      
      translations_to_check.each do |key|
        begin
          translation = I18n.t(key, raise: true)
          puts "  ✓ #{key}: #{translation}"
        rescue I18n::MissingTranslationData => e
          missing << key
          puts "  ✗ #{key}: MISSING"
        end
      end
      
      if missing.any?
        all_missing[locale] = missing
      end
    end
    
    if all_missing.any?
      puts "\n❌ Missing translations by locale:"
      all_missing.each do |locale, keys|
        puts "\n  #{locale}:"
        keys.each { |key| puts "    - #{key}" }
      end
      exit 1
    else
      puts "\n✅ All translations found in all locales!"
    end
  end
end
