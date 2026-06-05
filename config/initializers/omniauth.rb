# OmniAuth é middleware de boot, mas as credenciais OAuth são resolvidas EM
# RUNTIME via o `setup:` lambda — que roda a cada request/callback. Assim a tela
# de Integrações grava client_id/secret no `installation_configs` (compartilhado,
# via GlobalConfig) e o login social passa a funcionar SEM restart (igual ao BMS).
# Fallback para ENV mantém compatibilidade com quem configura por variável.
OmniAuth.config.allowed_request_methods = %i[get post]
OmniAuth.config.silence_get_warning = true

google_setup = lambda do |env|
  id = GlobalConfigService.load('GOOGLE_OAUTH_CLIENT_ID', ENV.fetch('GOOGLE_OAUTH_CLIENT_ID', nil))
  secret = GlobalConfigService.load('GOOGLE_OAUTH_CLIENT_SECRET', ENV.fetch('GOOGLE_OAUTH_CLIENT_SECRET', nil))
  strategy = env['omniauth.strategy']
  strategy.options[:client_id] = id if id.present?
  strategy.options[:client_secret] = secret if secret.present?
end

github_setup = lambda do |env|
  id = GlobalConfigService.load('GITHUB_OAUTH_CLIENT_ID', ENV.fetch('GITHUB_OAUTH_CLIENT_ID', nil))
  secret = GlobalConfigService.load('GITHUB_OAUTH_CLIENT_SECRET', ENV.fetch('GITHUB_OAUTH_CLIENT_SECRET', nil))
  strategy = env['omniauth.strategy']
  strategy.options[:client_id] = id if id.present?
  strategy.options[:client_secret] = secret if secret.present?
end

Rails.application.config.middleware.use OmniAuth::Builder do
  # Credenciais iniciais vazias — resolvidas em runtime pelo setup lambda.
  provider :google_oauth2, '', '', {
    provider_ignores_state: true,
    setup: google_setup
  }

  provider :github, '', '', {
    scope: 'user:email',
    provider_ignores_state: true,
    setup: github_setup
  }
end
