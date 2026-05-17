# Changelog

All notable changes to EvoAuth Service will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- N/A

### Changed

- N/A

### Fixed

- N/A

## [v1.0.0-rc3] - 2026-05-17

Release de estabilização — concentra correções de bugs em 2FA backup codes (500 + hash plaintext), boundary `account_owner` / `super_admin` em endpoints de roles (privilege escalation via delegation), aplicação runtime de configs SMTP/BMS/Resend, validação estruturada de senha na criação de usuário, e RBAC do role `agent` (drop de `pipelines.update`, backfill de `pipelines.read`). Também consolida a fundação do open-core via `EXTENSION_POINTS.md` + módulos de extensão estritos (`LoginGate`, `TokenClaims`), adiciona CRUD completo de roles com escopo `account_owner` e introduz permissões para `products.*` e `template_bundles`.

### Added

- **EVO-1381 — Módulos de extension point com LoginGate e TokenClaims** (#31) — implementação estrita dos pontos de extensão para Enterprise: `LoginGate` (hook chamado antes da emissão do token, permite negar login com motivo), `TokenClaims` (hook que adiciona claims customizadas ao JWT). Ambos com contratos estritos via duck-typing + erro explícito se a implementação Enterprise devolver shape inválido.
- **EVO-1375 — `EXTENSION_POINTS.md`** (#29) — documento declarando os pontos de extensão do auth-service. Contrato versionado.
- **EVO-1061 — CRUD completo de roles com escopo `account_owner`** — endpoints `index`/`show`/`create`/`update`/`destroy` para roles customizadas, todos limitados ao escopo da conta do `account_owner` requisitante. Inclui delegation de permissões com guard de privilege escalation.
- **EVO-1116 — Recurso `template_bundles` no RBAC** — permissões `template_bundles.read` / `manage` adicionadas via migration backfill, suporte ao recurso de export/import de templates do CRM.
- **`products.*` permissions** — recurso adicionado ao RBAC com backfill para roles existentes (`account_owner` recebe `manage`, `agent` recebe `read`).
- **`spec/db/seeds/rbac_spec.rb`** — regression guard para o permission set do role `agent` (EVO-1060). Detecta adições acidentais de permissões destrutivas (ex.: `pipelines.update` daria acesso a `archive` / `set_as_default`). Também pinneia o boundary `account_owner` / `super_admin` para garantir que o painel de installation-level config não vaze fora do `super_admin`.
- **`spec/controllers/roles_controller_spec.rb`** — boundary regression guards entre `account_owner` e `super_admin` (EVO-1060), garantindo que nenhum dos roles consegue escapar do seu escopo.

### Changed

- **EVO-1049 — Configurações SMTP/BMS/Resend aplicadas em runtime** (#24) — antes essas configurações eram lidas apenas no boot do container, exigindo restart para refletir mudanças feitas via UI. Agora são re-resolvidas a cada operação, permitindo ao operador alterar SMTP/BMS/Resend sem downtime.
- **Migration `20260513170000_add_pipelines_read_to_agent_role.rb`** — backfills `pipelines.read` no role `agent` para instalações já bootstrapped (EVO-1060). PROD roda `db:migrate` e não `db:seed`, então mudanças em `db/seeds/rbac.rb` que afetam role existente precisam vir junto com migration idempotente — mesma convenção do `20260505155854_promote_first_user_to_super_admin.rb`. Idempotente e reversível.
- **Docs** padronizados para Evolution Foundation 2026 (README, LICENSE, NOTICE, TRADEMARKS).
- **Docs (org)** — URLs do GitHub atualizadas de `EvolutionAPI` para `evolution-foundation`.

### Fixed

- **2FA backup codes — 500 + plaintext** (EVO-991) — o endpoint de listagem de backup codes retornava 500 (NoMethodError em campo nulo) e os codes eram armazenados em plaintext no DB. Corrigido com BCrypt hash + handling de campo nulo + review feedback de round 3 aplicado.
- **EVO-1063 — Password validation 422 estruturada** — antes a falha de validação de senha na criação de usuário retornava 422 sem campo machine-readable; frontend não conseguia mapear o erro para o campo correto. Agora a resposta inclui códigos estruturados (`password.too_short`, `password.missing_uppercase`, etc.) consumidos pelo checklist inline do frontend (EVO-1063).
- **Migration `add_message_template_permissions_to_account_owner`** — em fresh install falhava com `PG::UndefinedTable: roles` em determinada ordem de timestamp; agora cai silenciosamente quando a tabela ainda não existe (guard `table_exists?(:roles)`).
- **EVO-1060 — Agent role: `pipelines.read` granted, `pipelines.update` NOT granted** — fresh installs agora expõem a página `/pipelines` (e a entrada do sidebar) para agents. Drag-and-drop entre stages já era autorizado por `pipelines.read` sozinho — `pipelines.update` havia sido adicionado sob assumption errada e teria silenciosamente desbloqueado endpoints destrutivos (`archive`, `set_as_default`, rename de pipelines compartilhados, `PipelineServiceDefinitions` CRUD). Usuários `agent` existentes recebem a mudança automaticamente no próximo seed run (seed faz `destroy_all` e re-cria do array).

### Security

- **EVO-1061 — Privilege escalation via delegation no `roles_controller`** — o endpoint de update de roles permitia a um `account_owner` delegar permissões que ele próprio não detinha (caminho de privilege escalation por proxy). Fechado com check explícito: o usuário só pode delegar permissões que ele mesmo possui. Inclui spec de regressão.
- **EVO-1061 — Review blockers H1/M1-M3** — findings high/medium do round 2 do code review aplicados (escopo de account, validação de payload, error responses sem leakage).
- **2FA backup codes** — codes agora são hashed com BCrypt antes de gravar; antes ficavam em plaintext no banco (qualquer leitura do DB expunha o segundo fator do usuário).

## [v1.0.0-rc2] - 2026-05-05

### Added

- **Novo role `super_admin`** — installation-level operator. Detém todas as permissões do `account_owner` mais `installation_configs.manage` (a única permissão que dá acesso ao painel `/settings/admin`: SMTP, Storage, Social Login, OpenAI, Channels, Inbound Email, Frontend Runtime). Atribuído automaticamente ao usuário criado via setup wizard (bootstrap). Outros usuários criados depois pela UI continuam recebendo `account_owner` (sem acesso ao painel admin).
  - Implementação distribuída entre `db/seeds/rbac.rb` (fresh installs) e migration `20260505155854_promote_first_user_to_super_admin.rb` (PROD existente — única forma de chegar lá automaticamente, já que `db:seed` não roda em deploys).
  - A migration cria o role, sincroniza permissões via `ResourceActionsConfig.all_permission_keys`, **revoga `installation_configs.manage` do `account_owner`**, promove o primeiro user (`User.order(:created_at).first`) e **revoga tokens ativos** desse user para forçar relogin (caso contrário o JWT antigo com `role: account_owner` continuaria válido até expirar).
  - `SetupBootstrapService#assign_global_role` atualizado para atribuir `super_admin` (com fallback defensivo para `account_owner`).
  - Idempotente e reversível (`down` restaura o estado anterior).
### Fixed

- **POST `/api/v1/users` retornava 500 quando payload omitia `role`**: agora cai no padrão `agent` em vez de procurar `Role.find_by!(key: nil)` e levantar `RecordNotFound`. (#9)
- **`RoleSerializer` não expunha `key` / `system`**: o frontend depende dessas chaves para o select de roles funcionar; adicionados em `full` e `basic`. (#9)
- **Login sempre retornava 401 para usuários criados pela UI**: `UsersController#create` permitia `:password` em `new_user_params` mas não passava o valor para o `AgentBuilder.new(...)`. Como `AgentBuilder` cai no fallback `password.presence || "1!aA#{SecureRandom.alphanumeric(12)}"` quando `password` é `nil`, todo agente criado pela UI nascia com hash Argon2 aleatório que ninguém conhecia — login com a senha digitada nunca batia. Agora `password: new_user_params['password']` é encaminhado. `bulk_create` mantido inalterado (intencionalmente gera senha aleatória — fluxo de convite).
- **Migration `20260423162525_add_message_template_permissions_to_account_owner` falhava em fresh install com `PG::UndefinedTable: roles`**: a migration `init_schema` (timestamp `9025...` por typo histórico) cria a tabela `roles`, mas roda DEPOIS dessa por causa do timestamp futuro. Adicionado guard `ActiveRecord::Base.connection.table_exists?(:roles)` no `up` e `down` — fresh installs pulam a migration silenciosamente (o seed/bootstrap cobre depois), instalações existentes continuam rodando como antes.
- **`init_schema` (timestamp `9025...`) totalmente idempotente**: `make setup` em fresh install corria com race condition contra o `evo-bot-runtime` Go core, que tenta criar uma tabela `users` mínima ao subir. Quando o Go vencia a corrida, o `init_schema` falhava com `PG::DuplicateTable`. Migration reescrita com `if_not_exists: true` em todos os `create_table`, `add_index`, e helper `add_fk_if_missing` para foreign keys — agora o resultado final é determinístico independente de quem chega primeiro. (commit `ec736a9`)
- **EVO-1002 follow-up**: registradas as permissões `update_message_template` e `delete_message_template` no seeder de RBAC. (#5)
- **EVO-971**: gate de `/setup/status` agora considera tanto bootstrap quanto licensing — não só licensing. (#8)
- **EVO-967**: agentes convidados são auto-confirmados; lookup de role passou a tolerar role inexistente sem 500. (#3)

### Changed

- Workflow de CI publica também as imagens `develop` para staging. (#4)
- `installation_configs.manage` movida da lista de permissões padrão do `account_owner` para a lista `account_owner_exclusive` no `db/seeds/rbac.rb`. **Breaking change controlado**: account_owners criados depois deste release não veem mais o menu "Admin Settings" (comportamento esperado no Community single-tenant — só o bootstrap user / `super_admin` deve ter acesso). A migration de upgrade preserva acesso para o operador original.

## [v1.0.0-rc1] - 2026-04-24

### Added

- Primeiro release candidate público do `evo-auth-service-community` no contexto da família CRM Community.

### Changed

- Tag bootstrap a partir do código `2.0.0` original (`evo-auth-service`).

## [2.0.0] - 2025-01-20

### 🚀 Added

- **Bearer Token Authentication**: New modern authentication method using standard JWT Bearer tokens
- **New API Endpoints**:
  - `POST /api/v1/auth/login` - Modern login endpoint returning Bearer tokens
  - Enhanced `GET /api/v1/auth/me` - Now supports Bearer token authentication
- **Backward Compatibility**: Full support for existing DeviseTokenAuth headers
- **Multi-Authentication Support**: Service now accepts both Bearer tokens and legacy headers
- **Enhanced Security**: Improved token validation and account isolation
- **Public Repository**: Project is now open source and publicly available

### 🔧 Changed

- **Authentication Flow**: Simplified authentication with single Bearer token instead of multiple headers
- **API Responses**: Streamlined response format for login endpoints
- **Documentation**: Complete rewrite of authentication documentation
- **Integration Guide**: New comprehensive integration guide for developers

### 🛡️ Security

- **Token Validation**: Enhanced Bearer token validation with EvoAuth service integration
- **Account Scoping**: Improved account-based data isolation
- **Header Validation**: Support for both `Authorization: Bearer` and legacy `api_access_token` headers

### 📚 Documentation

- **README**: Updated with Bearer token examples and public repository information
- **API Documentation**: Comprehensive authentication guide with modern examples
- **Integration Guide**: New guide with examples for React, Vue, Node.js, Python, and more
- **Migration Guide**: Instructions for migrating from legacy authentication

### 🔄 Migration

- **Backward Compatible**: Existing applications continue to work without changes
- **Gradual Migration**: Applications can migrate to Bearer tokens at their own pace
- **Legacy Support**: DeviseTokenAuth headers remain fully supported

### 🏗️ Infrastructure

- **Public Access**: Repository is now publicly accessible
- **Open Source**: Licensed under Apache 2.0
- **Community**: Open for contributions and community involvement

## [1.0.0] - 2025-01-20

### Added

- **Authentication System**
  - JWT-based authentication with DeviseTokenAuth
  - User registration and login endpoints
  - Password reset functionality
  - Email confirmation system
  - Session management with token rotation

- **Multi-Factor Authentication (MFA)**
  - TOTP (Time-based One-Time Password) support
  - Email OTP (One-Time Password) support
  - Backup codes generation and verification
  - MFA setup and verification endpoints
  - Support for Google Authenticator and similar apps

- **OAuth 2.0 Provider**
  - Complete OAuth 2.0 authorization server (RFC 6749)
  - Authorization code flow with PKCE support
  - Client credentials flow
  - Token introspection and revocation
  - Dynamic client registration (RFC 7591)
  - Well-known discovery endpoints (RFC 8414)

- **Role-Based Access Control (RBAC)**
  - Flexible permission system
  - Role management with inheritance
  - User role assignments per account
  - Permission checking middleware
  - Super admin role with full access

- **Multi-Tenant Architecture**
  - Account-based data isolation
  - Account user management
  - Per-account feature flags
  - Account-scoped OAuth applications
  - Bulk user operations

- **Data Privacy & GDPR Compliance**
  - Data privacy consent management
  - User data export functionality
  - Data portability features
  - Deletion request handling
  - Privacy audit trails
  - GDPR-compliant data processing

- **Audit Logging System**
  - Comprehensive activity tracking
  - Authentication event logging
  - MFA event logging
  - RBAC change logging
  - Privacy action logging
  - System event logging with severity levels

- **Database-Driven Feature Flags**
  - Account-level feature management
  - Feature availability tracking
  - Dynamic feature enabling/disabling
  - Feature usage analytics

- **API Documentation**
  - Complete OpenAPI/Swagger documentation
  - Interactive API explorer
  - 200+ documented endpoints
  - Request/response examples
  - Authentication guides

- **Security Features**
  - Input validation and sanitization
  - SQL injection protection
  - XSS prevention
  - CSRF protection
  - Secure password hashing (bcrypt)
  - Token security with expiration

- **Internationalization**
  - Multi-language support (EN, PT-BR)
  - Localized error messages
  - Timezone handling
  - Currency support preparation

### Technical Implementation

- **Ruby 3.4.4** with **Rails 7.1**
- **PostgreSQL** database with optimized queries
- **Redis** for caching and session storage
- **Sidekiq** for background job processing
- **RSpec** testing framework with 95%+ coverage
- **RuboCop** for code style enforcement
- **Brakeman** for security analysis

### API Endpoints

- **Authentication**: 8 endpoints for login, logout, user info
- **Users**: 24 endpoints for user management
- **Accounts**: 30 endpoints for account operations
- **MFA**: 21 endpoints for multi-factor authentication
- **OAuth 2.0**: 32 endpoints for OAuth operations
- **Data Privacy**: 24 endpoints for GDPR compliance
- **Super Admin**: 31 endpoints for system administration
- **Audit Logs**: 11 endpoints for audit trail management
- **Permissions**: 16 endpoints for RBAC management
- **Well-Known**: 11 discovery endpoints for service metadata

### Security Enhancements

- Comprehensive audit logging for all user actions
- GDPR-compliant data handling and export
- Multi-factor authentication with backup codes
- OAuth 2.0 with PKCE for secure authorization
- Account-based data isolation for multi-tenancy
- Role-based permissions with granular control

### Documentation

- Professional README with quick start guide
- Comprehensive API documentation with Swagger
- Contributing guidelines for open source development
- Security policy for vulnerability reporting
- Code of conduct for community participation
- Apache License 2.0 for open source distribution

### Performance

- Optimized database queries with proper indexing
- Efficient caching strategies with Redis
- Background job processing for heavy operations
- Connection pooling for database efficiency
- Pagination for large data sets

### Developer Experience

- Complete test suite with high coverage
- Code quality tools (RuboCop, Brakeman)
- Comprehensive error handling
- Detailed logging for debugging
- Development seeds for quick setup

---

## Version History

- **1.0.0** (2025-01-20): Initial release with complete authentication system
- **0.1.0** (2025-01-15): Project initialization and basic setup

---

## Migration Guide

### From 0.x to 1.0.0

This is the initial stable release. No migration is needed as this is the first production-ready version.

### Database Migrations

All database migrations are included in the release. Run:

```bash
rails db:migrate
rails db:seed
```

### Configuration Changes

Ensure your `.env` file includes all required environment variables as documented in the README.

---

## Support

For questions about releases or upgrade paths:

- **Documentation**: [README.md](README.md)
- **API Docs**: [http://localhost:3001/api-docs](http://localhost:3001/api-docs)
- **Issues**: [GitHub Issues](https://github.com/EvolutionAPI/evo-auth-service/issues)
- **Email**: [support@evo-auth-service-community.com](mailto:support@evo-auth-service-community.com)

---

## Contributors

Thanks to all contributors who made this release possible:

- Development Team
- Security Researchers
- Documentation Contributors
- Community Members

---

**Note**: This changelog follows the [Keep a Changelog](https://keepachangelog.com/) format. Each release includes detailed information about new features, changes, deprecations, removals, fixes, and security updates.
