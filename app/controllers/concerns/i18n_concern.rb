# frozen_string_literal: true

module I18nConcern
  extend ActiveSupport::Concern

  # Safe translation that always returns a string
  # Falls back to humanized key if translation is missing
  def safe_translate(key, **options)
    I18n.t(key, **options)
  rescue I18n::MissingTranslationData => e
    Rails.logger.warn "Missing I18n translation: #{key}"
    
    # Return humanized version of the key
    fallback = key.to_s.split('.').last.humanize
    
    # If there are interpolation options, try to include them
    if options.any?
      "#{fallback} (#{options.map { |k, v| "#{k}: #{v}" }.join(', ')})"
    else
      fallback
    end
  end
  
  # Alias for convenience
  alias st safe_translate
end
