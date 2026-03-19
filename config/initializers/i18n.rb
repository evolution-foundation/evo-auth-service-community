# frozen_string_literal: true

# I18n Configuration for API-only mode
# All responses will be in English, frontend handles translations

# Set default locale to English
I18n.default_locale = :en

# Only allow English locale
I18n.available_locales = [:en]

# Enforce English fallback
I18n.fallbacks = [:en]

# In production, return key if translation is missing instead of raising error
# This prevents 500 errors if a translation key is missing
unless Rails.env.development? || Rails.env.test?
  I18n.exception_handler = lambda do |exception, locale, key, options|
    if exception.is_a?(I18n::MissingTranslation)
      # Log the missing translation for monitoring
      Rails.logger.warn "Missing I18n translation: #{key} (locale: #{locale})"
      
      # Return a safe default based on the key
      # Extract the last part of the key as a human-readable fallback
      key.to_s.split('.').last.humanize
    else
      raise exception
    end
  end
end
