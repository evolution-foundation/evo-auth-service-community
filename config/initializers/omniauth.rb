# O login social inicia via navegação do browser (GET em /auth/:provider). O
# OmniAuth 2 só permite POST no request-phase por padrão (CSRF). Liberamos GET
# para o fluxo redirect-based do devise_token_auth — o state/PKCE do provider
# cobre o CSRF da etapa de autorização.
OmniAuth.config.allowed_request_methods = %i[get post]
OmniAuth.config.silence_get_warning = true

Rails.application.config.middleware.use OmniAuth::Builder do
  # Google — só registra se houver client_id (sem credencial, OmniAuth retorna 404
  # no request phase de qualquer forma; o guard evita ruído e mantém o boot limpo).
  google_id = ENV.fetch('GOOGLE_OAUTH_CLIENT_ID', nil)
  if google_id.present?
    provider :google_oauth2, google_id, ENV.fetch('GOOGLE_OAUTH_CLIENT_SECRET', nil), {
      provider_ignores_state: true
    }
  end

  # GitHub — escopo user:email garante que o callback receba o e-mail (usado para
  # casar/criar o usuário em omniauth_callbacks_controller).
  github_id = ENV.fetch('GITHUB_OAUTH_CLIENT_ID', nil)
  if github_id.present?
    provider :github, github_id, ENV.fetch('GITHUB_OAUTH_CLIENT_SECRET', nil), {
      scope: 'user:email',
      provider_ignores_state: true
    }
  end
end
