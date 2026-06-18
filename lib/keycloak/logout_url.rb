module Keycloak
  class LogoutUrl
    def self.build(id_token_hint:, post_logout_redirect_uri:)
        return nil unless ENV['KEYCLOAK_ENABLED'] == 'true'
        
        params = {
            id_token_hint: id_token_hint,
            post_logout_redirect_uri: post_logout_redirect_uri,
            client_id: ENV['KEYCLOAK_CLIENT_ID']
        }.compact

        "#{ENV['KEYCLOAK_ISSUER']}/protocol/openid-connect/logout?#{URI.encode_www_form(params)}"
    end
  end
end
