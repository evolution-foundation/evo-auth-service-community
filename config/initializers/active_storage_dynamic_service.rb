# frozen_string_literal: true

# Overrides ActiveStorage::Blob.service so the storage provider chosen in Admin
# Settings → Storage is honoured at request time, not only at boot.
#
# GlobalConfigService.load caches the value for 60 s (via Rails.cache), so this
# is cheap on every call.  When the admin saves a new provider via the UI,
# GlobalConfig.set writes to the DB and the cache expires naturally within the
# TTL, after which all processes (web + Sidekiq) pick up the new value.
Rails.application.config.after_initialize do
  ActiveStorage::Blob.class_eval do
    class << self
      alias_method :_static_service, :service

      def service
        service_name = GlobalConfigService.load(
          'ACTIVE_STORAGE_SERVICE',
          ENV.fetch('ACTIVE_STORAGE_SERVICE', 'local')
        ).presence || 'local'
        key = service_name.to_sym
        (respond_to?(:services) && services[key]) || _static_service
      rescue StandardError
        _static_service
      end
    end
  end
end
