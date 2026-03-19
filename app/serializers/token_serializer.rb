# frozen_string_literal: true

module TokenSerializer
  extend self

  def oauth(token, user)
    {
      access_token: token.token,
      expires_in: token.expires_in,
      refresh_token: token.refresh_token,
      created_at: Time.at(token.created_at).iso8601,
      scopes: token.scopes.to_a,
      type: 'bearer',
      setup_active: Licensing::Runtime.context&.active? || false
    }
  end

  def access_token(token)
    {
      id: token.id,
      name: token.name,
      token: token.token,
      scopes: token.scopes,
      expires_at: nil,
      created_at: token.created_at,
      type: 'api_access_token'
    }
  end
end
