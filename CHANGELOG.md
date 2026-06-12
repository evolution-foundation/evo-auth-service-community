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

## [v1.0.0-rc6] - 2026-06-12

**Republish + feature batch.** Republishes `:latest` from a fresh build (the rc5-named image at Docker Hub had been desynced — see Operator action below) **and** ships eight commits accumulated on `develop` since rc5 was tagged. Operators upgrading from rc5 should expect both new features and bugfixes; operators upgrading from a poisoned `:latest` get those plus the actual rc5 content they thought they already had.

### Operator action

- **ACTION REQUIRED if you pulled `:latest` between 2026-05-27 and 2026-06-12 12:00 UTC.**
  The image at that period was the desynced rc5 build (digest `sha256:4c08dca7…`) which contained pre-rc4 source for `app/services/licensing/setup_gate.rb` (the old blocking version that returns `503 SETUP_REQUIRED`) and `db/migrate/20250819224900_init_schema.rb` (pre-`#36`, without the type-aware `add_fk_if_missing`). Pull again:
  ```sh
  docker pull evoapicloud/evo-auth-service-community:latest
  # Expected new digest: sha256:7bed488c1c2612dc3a395f2543c501ac485ec2d5d0ec7716d27f6c756d7d514e
  ```
- Symptoms you may have hit on the poisoned image: `DatatypeMismatch` boot crashes on legacy installs with `users.id integer`; permanent `503 SETUP_REQUIRED` on `/api/v1/*` when the licensing server was unreachable. Both are now correctly fixed in `:latest`.

### Added

- **EVO-1233 — message_templates RBAC resource + seed grants** (`54e15eb`).
- **EVO-1716 — message_templates resource actions** (`ab1e422`, #41).
- **Email confirmation flow + GitHub OAuth provider** (`a0e0702`) — adds Devise email-confirmation lifecycle and a GitHub identity provider in the OmniAuth chain. Existing logins unaffected; new signups receive a confirmation email if `SMTP_*` env vars are configured.
- **Bootstrap user gets enterprise `evolution_admin` grant** (`61b099e`) — first user created via `setup/register` is now assigned the `evolution_admin` role automatically. Cleaner self-hosted bootstrap; no manual grant step.
- **Smoke harness for `:latest`** (`b2a514a`, EVO-1404) — `docker-compose.smoke-fresh.yml` + `.github/workflows/smoke-fresh.yml`. Pulls `:latest`, runs `db:create && db:migrate && rails server` against fresh Postgres + Redis, asserts container reaches `healthy` + `/health` 200 + `/ready` 200. Triggered on PR changes to `Dockerfile`, `bin/docker-entrypoint`, `db/migrate/**`, the smoke compose or the smoke workflow.

### Changed

- **EVO-1551 round 2 — `mask_contact_pii` toggle hardening** (`49e62d0`, #39) — restricts the `mask_contact_pii` flip on `PATCH /api/v1/account` to admin roles (`enforce_admin_for_mask_pii_change` with effective-change gate). Earlier round 1 fix is upgraded to also deep-merge `settings`/`custom_attributes` so a partial PATCH no longer drops sibling keys.
- **OmniAuth runtime credential resolution** (`f2f2872`) — OAuth provider secrets are now resolved at request time from `runtime_configs` instead of at boot. Operators changing `GOOGLE_OAUTH_*` / `GITHUB_OAUTH_*` via the Admin UI no longer need a service restart for the new credentials to take effect.
- **`docker-publish.yml` — bypass cache on release paths** (`b2a514a`, EVO-1404) — added `no-cache: ${{ startsWith(github.ref, 'refs/tags/v') || github.ref == 'refs/heads/main' }}` to `docker/build-push-action`. Tag pushes (`v*.*.*`) and `main` branch pushes — both of which publish `:latest` — now rebuild from scratch. The `develop` branch keeps GHA cache for speed (it publishes only `:develop` / `:develop-<sha>`). This was the root-cause mitigation for the rc5 desync.

### Fixed

- **`bms_provider` URL construction** (`37c9097`, `fe084a5`) — BMS API URL is now read from runtime config and built dynamically per endpoint instead of hardcoded. Mail delivery via the BMS provider works against per-tenant BMS instances.
- **Image `:latest` actually contains rc5+ content** (EVO-1404 republish) — fresh build of `v1.0.0-rc6` replaces the desynced `:latest`. Verified inside the container: `setup_gate.rb` is the observability-only version (no `UNAVAILABLE_BODY`); `init_schema.rb` contains `column_type_incompatible?` and the `Skipping FK ... type mismatch` log line.



- N/A

### Fixed

- **EVO-1551 (round 2)** — fecha dois bypasses do mascaramento de PII de contato no `PATCH /api/v1/account`. (1) `enforce_admin_for_mask_pii_change` agora checa **mudança efetiva** (current vs incoming) em vez de mera presença da chave — agent não consegue mais derrubar `mask_contact_pii` mandando um body sem a chave. (2) `update` passa a fazer deep-merge em `settings` e `custom_attributes`; PATCH parcial deixou de apagar chaves irmãs (bug genérico de perda de dados). Specs novos em `spec/requests/api/v1/account_spec.rb` cobrem ambos os caminhos.

## [v1.0.0-rc5] - 2026-05-27

Hardening release for fresh-install scenarios. Three critical fixes from the multimport incident (2026-05-27) make EvoAuth survive cold starts where multiple services race against the shared database and the licensing server is unreachable. The auth-service no longer 500s when a sibling service has pre-created a stub `users` table, no longer blocks any request behind a licensing gate, and now actually processes its licensing Sidekiq queue so `SetupJob` / `HeartbeatJob` complete instead of being silently parked. Also ships AuthBridge 1.1.0 (extension point for Enterprise email lookup + sign-in) and a small batch of migration compatibility fixes.

### Highlights

- **Multimport / cold-start hardening (3 fixes)** — fresh installs that boot alongside other services sharing the same Postgres no longer break authentication. Stub `users(id integer)` tables created by sibling services (e.g. `evo-processor` SQLAlchemy `create_all`) are now detected and dropped before `InitSchema` runs, so the canonical schema (uuid PK, `mfa_method`, `encrypted_password`, `oauth_access_tokens`, …) is created intact. Combined with the SetupGate and Sidekiq queue fixes below, the auth-service boots and serves traffic cleanly in mixed-service environments even when the licensing server is temporarily unreachable.
- **Licensing never blocks a request** — `SetupGate` is downgraded from a hard 503 gate to a pure observability hook. Self-hosted Community installs no longer go down when the licensing server is unreachable — license state becomes telemetry, not an enforcement layer.
- **AuthBridge 1.1.0** — new strict extension points (`find_user_by_email`, `sign_in_request`) for Enterprise builds, contract-versioned via the existing `EXTENSION_POINTS.md` flow.

### Added

- **AuthBridge 1.1.0 — `find_user_by_email` + `sign_in_request`** (`e7c31e5`) — two new strict extension points exposed by `AuthBridge`. `find_user_by_email` lets an Enterprise implementation resolve a user from an alternate identity store (e.g. SSO directory) before the local lookup; `sign_in_request` lets it inject custom logic around request-time sign-in (audit, MFA elevation, just-in-time provisioning). Both follow the existing duck-typed contract with explicit error if the implementation returns an invalid shape. Documented in `EXTENSION_POINTS.md` (consumer-specific examples scrubbed in `1eed63e`).

### Changed

- **Docs — `EXTENSION_POINTS.md` scrub** (`1eed63e`) — removed consumer-specific examples from the AuthBridge 1.1.0 notes so the contract document stays generic and stable across Enterprise consumers.

### Fixed

- **Multimport stub `users` table drop before `InitSchema`** (`a962b3b`) — on fresh installs where another service (typically `evo-processor` via SQLAlchemy `create_all`) wins the race to Postgres, a minimal `users(id integer)` stub is created with the wrong primary-key type and no auth columns. `InitSchema` then silently aliased onto that stub, leaving the database without `oauth_access_tokens`, `mfa_method`, `encrypted_password`, etc. — every authentication path 500'd on `relation "oauth_access_tokens" does not exist`. The migration now detects the stub (integer-PK `users` with no auth columns) and drops it before `InitSchema` runs, so the canonical schema is created intact. Idempotent — does nothing on installations whose `users` table already matches the canonical shape.
- **`SetupGate` is observability, never enforcement** (`221097c`) — the licensing setup gate previously returned `503 SETUP_REQUIRED` on every non-bypass route when license context was inactive. On self-hosted Community this turned any licensing-server outage into a full auth outage. `SetupGate` now (a) attempts to rehydrate license context if inactive, (b) emits the observability signal regardless of the result, and (c) **always forwards the request**. License state becomes telemetry; no request is blocked by it.
- **Sidekiq licensing queue actually processed** (`6219e38`) — `licensing` was missing from `config/sidekiq.yml`, so `SetupJob` and `HeartbeatJob` were enqueued and silently parked forever. Result: `api_key` was never persisted after setup, and heartbeat retries never fired. The queue is now registered and processed alongside the default queues.
- **`add_fk_if_missing` type-aware for legacy integer PKs** (`39c92b3`, #36) — the FK helper now inspects the referenced PK type and matches the column type accordingly, so installations migrating from a historical integer-PK `users` table no longer fail with type-mismatch errors when adding foreign keys.
- **ActiveRecord migration version downgrade for compatibility** (`c725a96`, #37) — migration version downgraded to 7.1 to match the Rails version actually in use, preventing boot errors on `db:migrate` against environments still on 7.1.

### Notes for upgrade

- **Licensing no longer blocks any endpoint.** If your operational runbooks relied on the auth-service returning `503 SETUP_REQUIRED` while licensing was unreachable, update them — that signal is now an observability event, not a request-blocking response. License state still surfaces via logs/metrics for monitoring.
- **Fresh installs in mixed-service environments now boot cleanly** even when multiple services race against the shared Postgres. No action required for new installs.
- **If you are upgrading from an installation broken by the rc4 multimport race** (typical symptom: `relation "oauth_access_tokens" does not exist` on every login attempt; the `users` table exists but its PK is `integer` instead of `uuid` and the auth columns are missing), drop the cached stub `users` table manually before running `db:migrate` on rc5 — the migration's auto-detect handles the common shape, but if your stub diverges you may need to drop it explicitly. Back up first.
- **Sidekiq operators**: the `licensing` queue is now active. Ensure your Sidekiq worker process is started with the default queue list (or explicitly includes `licensing`) so `SetupJob` / `HeartbeatJob` are picked up.
- **AuthBridge consumers (Enterprise)**: extension contract bumped to 1.1.0 — see `EXTENSION_POINTS.md`. 1.0.x consumers continue to work; new hooks are opt-in.

## [v1.0.0-rc4] - 2026-05-25

MFA hardening release focused on plaintext backup-code remediation, plus licensing resilience, onboarding survey delivery, and runtime storage configuration. The post-EVO-991 cleanup forces re-setup for any user whose backup-code array still contains legacy plaintext entries; the licensing service now operates fail-open during outages instead of blocking logins; and Admin UI storage changes (S3/GCS/local) apply at runtime without restart.

### Added

- **EVO-1104 — Onboarding survey push** — implementation of onboarding-survey response push plus resume endpoint. Users that abandoned the flow can pick up where they left off, and submitted answers are forwarded to the collection service.
- **Licensing fail-open** — when the licensing server is unreachable (timeout, DNS, 5xx) the auth-service now operates in a short fail-open window instead of blocking logins. Reduces blast radius of incidents on the licensing server.

### Changed

- **Runtime storage provider** — storage settings (S3, GCS, local) saved via the Admin UI are applied to the running process without restart. A warn log is emitted whenever the service falls back to the default storage provider (EVO-1050).

### Fixed

- **EVO-991 — Plaintext backup codes from pre-fix deployments** — one-shot migration zeroes `otp_backup_codes` and clears `mfa_confirmed_at` for any user whose array still contains non-BCrypt (legacy plaintext) entries. Affected users are flagged with `mfa_setup_incomplete: true` in the user payload, and `auth_controller#login` bypasses the MFA challenge for that state (`mfa_enabled?` returns `false` when `mfa_confirmed_at` is `nil`) until re-setup completes. Specs cover the mixed-legacy array, post-migration empty state, and bypass regression.
- **EVO-1104 — Session cache not invalidated after MFA re-setup** — `complete_mfa_setup` now calls `TokenValidationService.invalidate_cache_for_user` so the session reflects `mfa_setup_incomplete: false` immediately after `verify_totp`, instead of waiting up to 5 minutes for the cache TTL.
- **Double-load guard and production hardening for extension points** — review-blocker fix preventing double-load of `LoginGate` and `TokenClaims` plus extra hardening in production paths.
- **ActiveRecord migration version downgrade 7.2 → 7.1** — migration version downgraded to match the Rails version actually in use. Avoids boot errors when running `db:migrate` against environments still on 7.1.

### Security

- Plaintext backup codes may have been stored on deployments prior to the EVO-991 fix. The migration in this release invalidates those records and forces affected users to re-setup their MFA. If you enabled MFA before v1.0.0-rc4, you will be prompted to set up TOTP again on next login. Recommended as a precaution — not a response to a confirmed leak.

## [v1.0.0-rc3] - 2026-05-17

Stabilization release — focuses on bug fixes in 2FA backup codes (500 + plaintext hash), `account_owner` / `super_admin` boundary on role endpoints (privilege escalation via delegation), runtime application of SMTP/BMS/Resend configs, structured password validation on user creation, and `agent` role RBAC (drop of `pipelines.update`, backfill of `pipelines.read`). Also consolidates the open-core foundation via `EXTENSION_POINTS.md` + strict extension modules (`LoginGate`, `TokenClaims`), adds full role CRUD scoped to `account_owner`, and introduces permissions for `products.*` and `template_bundles`.

### Added

- **EVO-1381 — Extension point modules with LoginGate and TokenClaims** (#31) — strict implementation of extension points for Enterprise: `LoginGate` (hook called before token issuance, allows denying login with a reason), `TokenClaims` (hook that adds custom claims to the JWT). Both with strict contracts via duck-typing + explicit error if the Enterprise implementation returns an invalid shape.
- **EVO-1375 — `EXTENSION_POINTS.md`** (#29) — document declaring the extension points of the auth-service. Versioned contract.
- **EVO-1061 — Full role CRUD scoped to `account_owner`** — `index`/`show`/`create`/`update`/`destroy` endpoints for custom roles, all limited to the account scope of the requesting `account_owner`. Includes permission delegation with privilege escalation guard.
- **EVO-1116 — `template_bundles` resource in RBAC** — `template_bundles.read` / `manage` permissions added via migration backfill, supporting the CRM template export/import feature.
- **`products.*` permissions** — resource added to RBAC with backfill for existing roles (`account_owner` gets `manage`, `agent` gets `read`).
- **`spec/db/seeds/rbac_spec.rb`** — regression guard for the `agent` role permission set (EVO-1060). Detects accidental additions of destructive permissions (e.g., `pipelines.update` would grant access to `archive` / `set_as_default`). Also pins the `account_owner` / `super_admin` boundary to ensure the installation-level config panel does not leak outside `super_admin`.
- **`spec/controllers/roles_controller_spec.rb`** — boundary regression guards between `account_owner` and `super_admin` (EVO-1060), ensuring neither role can escape its scope.

### Changed

- **EVO-1049 — SMTP/BMS/Resend settings applied at runtime** (#24) — previously these settings were read only at container boot, requiring a restart to reflect changes made via the UI. Now they are re-resolved on every operation, allowing the operator to change SMTP/BMS/Resend without downtime.
- **Migration `20260513170000_add_pipelines_read_to_agent_role.rb`** — backfills `pipelines.read` on the `agent` role for already-bootstrapped installations (EVO-1060). PROD runs `db:migrate` and not `db:seed`, so changes to `db/seeds/rbac.rb` that affect an existing role must ship with an idempotent migration — same convention as `20260505155854_promote_first_user_to_super_admin.rb`. Idempotent and reversible.
- **Docs** standardized for Evolution Foundation 2026 (README, LICENSE, NOTICE, TRADEMARKS).
- **Docs (org)** — GitHub URLs updated from `EvolutionAPI` to `evolution-foundation`.

### Fixed

- **2FA backup codes — 500 + plaintext** (EVO-991) — the backup-codes listing endpoint returned 500 (NoMethodError on a nil field) and codes were stored in plaintext in the DB. Fixed with BCrypt hashing + nil-field handling + applied round 3 review feedback.
- **EVO-1063 — Structured 422 password validation** — previously the password validation failure on user creation returned 422 without a machine-readable field; the frontend could not map the error to the correct field. Now the response includes structured codes (`password.too_short`, `password.missing_uppercase`, etc.) consumed by the inline checklist on the frontend (EVO-1063).
- **Migration `add_message_template_permissions_to_account_owner`** — on fresh install it failed with `PG::UndefinedTable: roles` for a particular timestamp ordering; now it falls through silently when the table does not yet exist (`table_exists?(:roles)` guard).
- **EVO-1060 — Agent role: `pipelines.read` granted, `pipelines.update` NOT granted** — fresh installs now expose the `/pipelines` page (and the sidebar entry) to agents. Drag-and-drop between stages was already authorized by `pipelines.read` alone — `pipelines.update` had been added under a wrong assumption and would have silently unlocked destructive endpoints (`archive`, `set_as_default`, rename of shared pipelines, `PipelineServiceDefinitions` CRUD). Existing `agent` users receive the change automatically on the next seed run (the seed does `destroy_all` and re-creates from the array).

### Security

- **EVO-1061 — Privilege escalation via delegation in `roles_controller`** — the role update endpoint allowed an `account_owner` to delegate permissions they did not themselves hold (proxy privilege escalation path). Closed with an explicit check: a user can only delegate permissions they themselves possess. Includes a regression spec.
- **EVO-1061 — Review blockers H1/M1-M3** — high/medium findings from round 2 of the code review applied (account scope, payload validation, error responses without leakage).
- **2FA backup codes** — codes are now hashed with BCrypt before storage; previously they sat in plaintext in the database (any DB read exposed the user's second factor).

## [v1.0.0-rc2] - 2026-05-05

### Added

- **New `super_admin` role** — installation-level operator. Holds all `account_owner` permissions plus `installation_configs.manage` (the only permission that grants access to the `/settings/admin` panel: SMTP, Storage, Social Login, OpenAI, Channels, Inbound Email, Frontend Runtime). Automatically assigned to the user created via the setup wizard (bootstrap). Other users created later via the UI continue to receive `account_owner` (no access to the admin panel).
  - Implementation split between `db/seeds/rbac.rb` (fresh installs) and migration `20260505155854_promote_first_user_to_super_admin.rb` (existing PROD — the only way to get there automatically, since `db:seed` does not run on deploys).
  - The migration creates the role, syncs permissions via `ResourceActionsConfig.all_permission_keys`, **revokes `installation_configs.manage` from `account_owner`**, promotes the first user (`User.order(:created_at).first`) and **revokes active tokens** for that user to force re-login (otherwise the old JWT with `role: account_owner` would remain valid until expiry).
  - `SetupBootstrapService#assign_global_role` updated to assign `super_admin` (with a defensive fallback to `account_owner`).
  - Idempotent and reversible (`down` restores the previous state).
### Fixed

- **POST `/api/v1/users` returned 500 when the payload omitted `role`**: now falls back to the `agent` default instead of looking up `Role.find_by!(key: nil)` and raising `RecordNotFound`. (#9)
- **`RoleSerializer` did not expose `key` / `system`**: the frontend depends on these keys for the role select to work; added to `full` and `basic`. (#9)
- **Login always returned 401 for users created via the UI**: `UsersController#create` permitted `:password` in `new_user_params` but did not pass the value to `AgentBuilder.new(...)`. Since `AgentBuilder` falls back to `password.presence || "1!aA#{SecureRandom.alphanumeric(12)}"` when `password` is `nil`, every agent created via the UI was born with a random Argon2 hash that nobody knew — login with the typed password never matched. Now `password: new_user_params['password']` is forwarded. `bulk_create` left unchanged (intentionally generates a random password — invite flow).
- **Migration `20260423162525_add_message_template_permissions_to_account_owner` failed on fresh install with `PG::UndefinedTable: roles`**: the `init_schema` migration (timestamp `9025...` due to a historical typo) creates the `roles` table, but runs AFTER this one because of the future timestamp. Added `ActiveRecord::Base.connection.table_exists?(:roles)` guard on `up` and `down` — fresh installs skip the migration silently (the seed/bootstrap covers it later), existing installations keep running as before.
- **`init_schema` (timestamp `9025...`) fully idempotent**: `make setup` on fresh install raced against the `evo-bot-runtime` Go core, which tries to create a minimal `users` table at startup. When the Go service won the race, `init_schema` failed with `PG::DuplicateTable`. Migration rewritten with `if_not_exists: true` on every `create_table`, `add_index`, and an `add_fk_if_missing` helper for foreign keys — the final result is now deterministic regardless of who arrives first. (commit `ec736a9`)
- **EVO-1002 follow-up**: registered the `update_message_template` and `delete_message_template` permissions in the RBAC seeder. (#5)
- **EVO-971**: the `/setup/status` gate now considers both bootstrap and licensing — not only licensing. (#8)
- **EVO-967**: invited agents are auto-confirmed; role lookup now tolerates a missing role without returning 500. (#3)

### Changed

- CI workflow also publishes `develop` images to staging. (#4)
- `installation_configs.manage` moved from the `account_owner` default permission list to the `account_owner_exclusive` list in `db/seeds/rbac.rb`. **Controlled breaking change**: account_owners created after this release no longer see the "Admin Settings" menu (expected behavior in single-tenant Community — only the bootstrap user / `super_admin` should have access). The upgrade migration preserves access for the original operator.

## [v1.0.0-rc1] - 2026-04-24

### Added

- First public release candidate of `evo-auth-service-community` in the context of the CRM Community family.

### Changed

- Bootstrap tag from the original `2.0.0` code (`evo-auth-service`).

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

[Unreleased]: https://github.com/evolution-foundation/evo-auth-service-community/compare/v1.0.0-rc5...HEAD
[v1.0.0-rc5]: https://github.com/evolution-foundation/evo-auth-service-community/compare/v1.0.0-rc4...v1.0.0-rc5
[v1.0.0-rc4]: https://github.com/evolution-foundation/evo-auth-service-community/compare/v1.0.0-rc3...v1.0.0-rc4
[v1.0.0-rc3]: https://github.com/evolution-foundation/evo-auth-service-community/compare/v1.0.0-rc2...v1.0.0-rc3
[v1.0.0-rc2]: https://github.com/evolution-foundation/evo-auth-service-community/compare/v1.0.0-rc1...v1.0.0-rc2
[v1.0.0-rc1]: https://github.com/evolution-foundation/evo-auth-service-community/releases/tag/v1.0.0-rc1
