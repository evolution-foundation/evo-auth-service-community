# frozen_string_literal: true

module AccessTokenSerializer
  extend self

  def full(access_token)
    return nil unless access_token

    {
      id: access_token.id,
      owner_id: access_token.owner_id,
      owner_type: access_token.owner_type,
      name: access_token.name,
      token: access_token.token,
      scopes: access_token.scopes,
      created_at: access_token.created_at,
      updated_at: access_token.updated_at
    }
  end

  def basic(access_token)
    return nil unless access_token

    {
      id: access_token.id,
      name: access_token.name,
      scopes: access_token.scopes,
      created_at: access_token.created_at
    }
  end
end
