# frozen_string_literal: true

module LicensingSetupConcern
  extend ActiveSupport::Concern

  private

  def attempt_setup(user)
    store = Licensing::Store.new

    if Licensing::Runtime.context&.active?
      store.load_or_create_instance_id
      store.load_runtime_data
      return
    end

    return if RuntimeConfig.account.nil?

    return if Licensing::Activation.try_reactivate(store: store)

    # Fully asynchronous — login must never wait on the licensing server.
    # SetupJob retries internally and the heartbeat path will pick up later
    # if it cannot reach the server.
    Licensing::SetupJob.perform_later(
      email:     user.email,
      name:      user.name.presence || user.email,
      client_ip: request.remote_ip
    )
  rescue StandardError => e
    Rails.logger.warn "[LicensingSetup] Setup attempt failed: #{e.message}"
  end
end
