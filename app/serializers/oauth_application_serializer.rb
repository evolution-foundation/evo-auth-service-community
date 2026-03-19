# frozen_string_literal: true

module OauthApplicationSerializer
  extend self

  def full(oauth_app)
    return nil unless oauth_app

    {
      id: oauth_app.id,
      name: oauth_app.name,
      uid: oauth_app.uid,
      redirect_uri: oauth_app.redirect_uri,
      scopes: oauth_app.scopes,
      confidential: oauth_app.confidential,
      created_at: oauth_app.created_at,
      updated_at: oauth_app.updated_at
    }
  end

  def basic(oauth_app)
    return nil unless oauth_app

    {
      id: oauth_app.id,
      name: oauth_app.name,
      uid: oauth_app.uid,
      scopes: oauth_app.scopes
    }
  end

  def with_secret(oauth_app)
    return nil unless oauth_app

    full(oauth_app).merge(secret: oauth_app.secret)
  end
end
