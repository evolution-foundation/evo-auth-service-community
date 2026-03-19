# frozen_string_literal: true

# Configure session store for OAuth and API authentication
Rails.application.config.session_store :cookie_store, 
                                      key: '_evo_auth_service_session',
                                      secure: !Rails.env.development?,
                                      httponly: true,
                                      same_site: :strict
