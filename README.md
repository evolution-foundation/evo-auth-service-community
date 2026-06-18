<p align="center">
  <a href="https://evolutionfoundation.com.br">
    <img src="./public/hover-evolution.png" alt="Evolution Foundation" />
  </a>
</p>

<h1 align="center">Evo CRM Auth Service</h1>

<p align="center">
  Authentication, RBAC, OAuth 2.0 and token issuance service for the Evo CRM Community.
</p>

<p align="center">
  <a href="https://github.com/evolution-foundation/evo-auth-service-community/releases/latest"><img src="https://img.shields.io/github/v/release/evolution-foundation/evo-auth-service-community?include_prereleases&label=version&color=00ffa7" alt="Latest version" /></a>
  <a href="https://opensource.org/licenses/Apache-2.0"><img src="https://img.shields.io/badge/License-Apache%202.0-blue.svg" alt="License: Apache 2.0" /></a>
  <a href="https://docs.evolutionfoundation.com.br"><img src="https://img.shields.io/badge/Docs-evolutionfoundation.com.br-00ffa7" alt="Documentation" /></a>
  <a href="https://evolutionfoundation.com.br/community"><img src="https://img.shields.io/badge/Community-Join%20us-white" alt="Community" /></a>
</p>

<p align="center">
  <a href="https://evolutionfoundation.com.br">Website</a> &middot;
  <a href="https://docs.evolutionfoundation.com.br">Documentation</a> &middot;
  <a href="https://evolutionfoundation.com.br/community">Community</a> &middot;
  <a href="mailto:suporte@evofoundation.com.br">Support</a>
</p>

---

## About

**Evo CRM Auth Service** is the authentication and authorization microservice of the Evo CRM Community. Built on Ruby on Rails 7.1, it provides Bearer token authentication, OAuth 2.0 (Doorkeeper), Multi-Factor Authentication (TOTP, Email OTP, backup codes), Role-Based Access Control with simple `account_owner` / `agent` roles, and LGPD-compliant audit logging.

## Part of the Evo CRM Community

Evo CRM Auth Service is part of the [Evo CRM Community](https://github.com/evolution-foundation/evo-crm-community) ecosystem maintained by Evolution Foundation. To use the full stack, clone the umbrella repository with submodules:

```bash
git clone --recurse-submodules git@github.com:evolution-foundation/evo-crm-community.git
```

The Community Edition is **single-tenant** by design — one account, no multi-tenancy overhead, no super-admin, no billing or plans. The role hierarchy is simple: `account_owner` and `agent`.

---

## Features

### Authentication
- Bearer token authentication with JWT
- OAuth 2.0 provider via Doorkeeper (RFC 6749)
- Multi-Factor Authentication (TOTP, Email OTP, backup codes)
- Legacy DeviseTokenAuth support for backward compatibility
- Well-Known discovery endpoints (RFC 8414)

### Authorization
- Role-Based Access Control (RBAC): `account_owner` and `agent`
- Token rotation and secure session management

### Compliance
- LGPD-compliant data privacy controls
- Comprehensive audit logging for all user actions
- Database-driven feature flags

### API
- RESTful API with documented endpoints
- OpenAPI / Swagger documentation
- Webhook support for real-time notifications
- Multi-language support (EN, PT-BR)

---

## Quick Start

### Prerequisites

- **Ruby** 3.4.4
- **Rails** 7.1+
- **PostgreSQL** 12+
- **Redis** 6+

### Installation

```bash
git clone git@github.com:evolution-foundation/evo-auth-service-community.git
cd evo-auth-service-community

# Install dependencies
bundle install

# Configure database
rails db:create
rails db:migrate
rails db:seed

# Start server
rails server -p 3001
```

The service will be available at `http://localhost:3001`.

> **Default credentials**: configured in `db/seeds.rb`. Review and change them before any deployment.

### API documentation

Once running, Swagger UI is available at:

```
http://localhost:3001/api-docs
```

---

## Configuration

Create a `.env` file:

```bash
# Database
DATABASE_URL=postgresql://user:pass@localhost:5432/evo_auth_service_development

# Redis
REDIS_URL=redis://localhost:6379/1

# JWT secret
DEVISE_JWT_SECRET_KEY=your_super_secret_jwt_key

# OAuth
DOORKEEPER_SECRET_KEY=your_doorkeeper_secret_key

# Frontend URL (CORS and OAuth callbacks)
FRONTEND_URL=http://localhost:3000

# Email (MFA and notifications)
SMTP_HOST=smtp.example.com
SMTP_PORT=587
SMTP_USERNAME=your_email@example.com
SMTP_PASSWORD=your_app_password
```

See `.env.example` for all available variables.

---

## Authentication examples

### Bearer token (recommended)

```bash
# Login
curl -X POST http://localhost:3001/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "user@example.com", "password": "password"}'

# Use the token
curl -X GET http://localhost:3001/api/v1/auth/me \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"
```

### API access token (server-to-server)

```bash
curl -X GET http://localhost:3001/api/v1/users \
  -H "api_access_token: YOUR_API_TOKEN"
```

### OAuth 2.0 Bearer token (third-party apps)

```bash
curl -X GET http://localhost:3001/api/v1/users \
  -H "Authorization: Bearer YOUR_OAUTH_TOKEN"
```

---

## Architecture

The auth service issues tokens consumed by all other services in the Evo CRM Community ecosystem:

```
                    ┌──────────────────────────┐
                    │  Evo CRM Auth Service    │ ← (you are here)
                    │  (token issuance, RBAC)  │
                    └────────────┬─────────────┘
                                 │ Bearer token
          ┌──────────────────────┼──────────────────────┐
          ↓                      ↓                      ↓
   evo-ai-crm-community  evo-ai-core-service   evo-ai-processor
   (conversations,       (agents, tools,       (agent execution,
    contacts)             API keys, folders)    sessions)
```

Inter-service communication uses Bearer token authentication. Tokens issued by this service are forwarded between services — no `account-id` header required.

---

## Key Endpoints

| Endpoint | Description |
|---|---|
| `POST /api/v1/auth/login` | User authentication (Bearer token) |
| `GET /api/v1/auth/me` | Get current user info |
| `POST /auth/sign_in` | Legacy DeviseTokenAuth |
| `POST /api/v1/mfa/setup_totp` | Setup TOTP MFA |
| `GET /oauth/authorize` | OAuth 2.0 authorization |
| `POST /oauth/token` | OAuth 2.0 token exchange |
| `GET /.well-known/oauth-authorization-server` | OAuth server metadata |

---

## Testing

```bash
# All tests
bundle exec rspec

# Specific file
bundle exec rspec spec/models/user_spec.rb

# With coverage
COVERAGE=true bundle exec rspec
```

---

## Keycloak Integration

> ⚠️ **Role type terminology is not a 1:1 mapping.**
>
> Evolution's internal role types are `user` (system-wide roles such as `super_admin` and `account_owner`) and `account` (account-level roles such as `agent`).
>
> Keycloak, on the other hand, distinguishes between `realm` roles and `client` roles. When importing roles from Keycloak, keep in mind that these concepts are not linearly equivalent: a Keycloak realm role may map to either an Evolution `user` role or an `account` role depending on its scope and usage. Review the role type carefully before running the `keycloak:create_roles` rake task.

## Documentation

| Resource | Link |
|---|---|
| Website | [evolutionfoundation.com.br](https://evolutionfoundation.com.br) |
| Documentation | [docs.evolutionfoundation.com.br](https://docs.evolutionfoundation.com.br) |
| Community | [evolutionfoundation.com.br/community](https://evolutionfoundation.com.br/community) |
| Changelog | [CHANGELOG.md](./CHANGELOG.md) |
| Contributing | [CONTRIBUTING.md](./CONTRIBUTING.md) |
| Security | [SECURITY.md](./SECURITY.md) |

---

## Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](./CONTRIBUTING.md) for guidelines on how to submit issues, propose features, and open pull requests.

Join our [community](https://evolutionfoundation.com.br/community) to discuss ideas and collaborate.

---

## Security

For security issues, **do not open a public issue**. Email **suporte@evofoundation.com.br** or use GitHub's private vulnerability reporting. See [SECURITY.md](./SECURITY.md) for details.

---

## Acknowledgments

This service builds on excellent open-source software:
- [DeviseTokenAuth](https://github.com/lynndylanhurley/devise_token_auth) — JWT authentication
- [Doorkeeper](https://github.com/doorkeeper-gem/doorkeeper) — OAuth 2.0 provider
- [ROTP](https://github.com/mdp/rotp) — TOTP implementation
- [RSwag](https://github.com/rswag/rswag) — API documentation

---

## License

Evo CRM Auth Service is licensed under the Apache License 2.0. See [LICENSE](./LICENSE) for details.

## Trademarks

"Evolution Foundation", "Evolution" and "Evo CRM Auth Service" are trademarks of Evolution Foundation. See [TRADEMARKS.md](./TRADEMARKS.md) for the brand assets policy.

Third-party attributions are documented in [NOTICE](./NOTICE).

---

<p align="center">
  Made by <a href="https://evolutionfoundation.com.br">Evolution Foundation</a> · © 2026
</p>
