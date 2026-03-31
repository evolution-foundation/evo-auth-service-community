# 🔐 EvoAuth Service

[![Ruby Version](https://img.shields.io/badge/ruby-3.4.4-red.svg)](https://www.ruby-lang.org/)
[![Rails Version](https://img.shields.io/badge/rails-7.1.x-red.svg)](https://rubyonrails.org/)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![API Documentation](https://img.shields.io/badge/API-Swagger-green.svg)](http://localhost:3001/api-docs)
[![Test Coverage](https://img.shields.io/badge/coverage-95%25-brightgreen.svg)](#testing)

> **A modern, secure, and scalable authentication service built with Ruby on Rails**

EvoAuth Service is a comprehensive authentication and authorization solution designed for modern applications. It provides OAuth 2.0, Multi-Factor Authentication (MFA), Role-Based Access Control (RBAC), and GDPR compliance out of the box.

## ✨ Features

### 🔑 **Authentication & Authorization**
- **Bearer Token Authentication** with standard JWT tokens
- **Legacy DeviseTokenAuth Support** for backward compatibility
- **OAuth 2.0 Provider** with Doorkeeper (RFC 6749)
- **Multi-Factor Authentication** (TOTP, Email OTP, Backup Codes)
- **Role-Based Access Control** (RBAC) with granular permissions
- **Account Isolation** for multi-tenant applications

### 🛡️ **Security & Compliance**
- **GDPR/LGPD Compliance** with data privacy controls
- **Comprehensive Audit Logging** for all user actions
- **Database-driven Feature Flags** for controlled rollouts
- **Secure Session Management** with token rotation
- **Well-Known Discovery** endpoints (RFC 8414)

### 🌐 **API & Integration**
- **RESTful API** with 200+ documented endpoints
- **OpenAPI/Swagger Documentation** for easy integration
- **Webhook Support** for real-time notifications
- **Multi-language Support** (EN, PT-BR)
- **Account-scoped Operations** for data isolation

### 📊 **Monitoring & Observability**
- **Structured Audit Trails** with detailed event tracking
- **Health Check Endpoints** for monitoring
- **Request ID Tracking** for debugging
- **Performance Metrics** ready for APM integration

## 🚀 Quick Start

### Prerequisites

- Ruby 3.4.4+
- Rails 7.1+
- PostgreSQL 12+
- Redis 6+

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/EvolutionAPI/evo-auth-service.git
   cd evo-auth-service
   ```

2. **Install dependencies**
   ```bash
   bundle install
   ```

3. **Setup database**
   ```bash
   rails db:create
   rails db:migrate
   rails db:seed
   ```

4. **Start the server**
   ```bash
   rails server -p 3001
   ```

5. **Access the API documentation**
   ```
   http://localhost:3001/api-docs
   ```

### Default Credentials

After running `rails db:seed`, you can use these default credentials:

```
Email: admin@evo-auth-service.com
Password: password123
```

## 📖 Documentation

### 📚 Complete Documentation Suite

| Document | Description |
|----------|-------------|
| **[API Documentation](http://localhost:3001/api-docs)** | Interactive Swagger UI documentation |
| **[Integration Guide](docs/INTEGRATION_GUIDE.md)** | Complete integration guide with examples |
| **[Migration Guide](docs/MIGRATION_GUIDE.md)** | Migrate from legacy to Bearer tokens |
| **[Authentication API](docs/api/authentication.md)** | Detailed authentication endpoints |
| **[Changelog](CHANGELOG.md)** | Version history and release notes |

### Interactive Documentation
Visit [http://localhost:3001/api-docs](http://localhost:3001/api-docs) for interactive Swagger UI documentation.

### Key Endpoints

| Endpoint | Description |
|----------|-------------|
| `POST /api/v1/auth/login` | User authentication (Bearer token) |
| `GET /api/v1/auth/me` | Get current user info |
| `POST /auth/sign_in` | Legacy authentication (DeviseTokenAuth) |
| `POST /api/v1/mfa/setup_totp` | Setup TOTP MFA |
| `GET /oauth/authorize` | OAuth 2.0 authorization |
| `POST /oauth/token` | OAuth 2.0 token exchange |
| `GET /.well-known/oauth-authorization-server` | OAuth server metadata |

### Authentication

EvoAuth Service supports multiple authentication methods:

#### 1. Bearer Token Authentication (Recommended)
```bash
# Login and get Bearer token
curl -X POST http://localhost:3001/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "user@example.com", "password": "password"}'

# Use Bearer token for API requests
curl -X GET http://localhost:3001/api/v1/auth/me \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"
```

#### 2. Legacy DeviseTokenAuth (Backward Compatibility)
```bash
curl -X POST http://localhost:3001/auth/sign_in \
  -H "Content-Type: application/json" \
  -d '{"email": "user@example.com", "password": "password"}'
```

#### 3. API Access Token (Server-to-Server)
```bash
curl -X GET http://localhost:3001/api/v1/users \
  -H "api_access_token: YOUR_API_TOKEN"
```

#### 4. OAuth 2.0 Bearer Token (Third-party Apps)
```bash
curl -X GET http://localhost:3001/api/v1/users \
  -H "Authorization: Bearer YOUR_OAUTH_TOKEN"
```

## 🔧 Configuration

### Environment Variables

Create a `.env` file in the root directory:

```env
# Database
DATABASE_URL=postgresql://username:password@localhost:5432/evo_auth_service_development

# Redis
REDIS_URL=redis://localhost:6379/1

# JWT Secret
DEVISE_JWT_SECRET_KEY=your_super_secret_jwt_key_here

# OAuth
DOORKEEPER_SECRET_KEY=your_doorkeeper_secret_key_here

# Frontend URL (for CORS and OAuth callbacks)
FRONTEND_URL=http://localhost:3000

# Email (for MFA and notifications)
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USERNAME=your_email@gmail.com
SMTP_PASSWORD=your_app_password

# Optional: Enable account signup
ENABLE_ACCOUNT_SIGNUP=true

# Optional: Super Admin email
SUPER_ADMIN_EMAIL=admin@evo-auth-service.com
```

### Feature Flags

EvoAuth Service uses database-driven feature flags. Manage them via:

```ruby
# Enable a feature for an account
account.enable_feature!('advanced_mfa')

# Check if feature is enabled
account.feature_enabled?('advanced_mfa')

# Available features
Feature.available_features
```

## 🏗️ Architecture

### Multi-Tenant Design

EvoAuth Service is built with multi-tenancy in mind:

- **Resource Separation**: Each account has isolated users, roles, and OAuth applications
- **Feature Flags**: Features can be enabled/disabled per account
- **Audit Trails**: All actions are logged with account context

### Database Schema

Key models and relationships:

```
Account (1) ──── (N) AccountUser (N) ──── (1) User
   │                                         │
   │                                         ├── UserRole ──── Role ──── Permission
   │                                         │
   └── OauthApplication                      ├── DataPrivacyConsent
                                            │
                                            └── AuditLog
```

### Security Model

- **JWT Tokens**: Stateless authentication with configurable expiration
- **OAuth 2.0**: Industry-standard authorization with PKCE support
- **MFA**: TOTP (Google Authenticator) and Email OTP
- **RBAC**: Granular permissions with role inheritance
- **Audit Logging**: Comprehensive activity tracking

## 🧪 Testing

Run the test suite:

```bash
# Run all tests
bundle exec rspec

# Run with coverage
COVERAGE=true bundle exec rspec

# Run specific test file
bundle exec rspec spec/models/user_spec.rb

# Run tests matching pattern
bundle exec rspec spec/requests/api/v1/auth_spec.rb
```

### Test Coverage

Current test coverage: **95%+**

- Unit tests for all models
- Integration tests for API endpoints
- Authentication and authorization tests
- MFA workflow tests
- RBAC permission tests

## 🔒 Security

### Reporting Security Issues

Please report security vulnerabilities to [security@evo-auth-service.com](mailto:security@evo-auth-service.com). See [SECURITY.md](SECURITY.md) for details.

### Security Features

- **Input Validation**: All inputs are validated and sanitized
- **SQL Injection Protection**: Using ActiveRecord ORM
- **XSS Protection**: Content Security Policy headers
- **CSRF Protection**: Rails built-in CSRF protection
- **Rate Limiting**: Configurable rate limits per endpoint
- **Secure Headers**: Security headers for all responses

## 🌍 Internationalization

EvoAuth Service supports multiple languages:

- **English** (en) - Default
- **Portuguese Brazil** (pt-BR)
- **Spanish** (es) - Planned

Add new translations in `config/locales/`:

```yaml
# config/locales/pt-BR.yml
pt-BR:
  auth:
    login_success: "Login realizado com sucesso"
    invalid_credentials: "Credenciais inválidas"
```

## 🤝 Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

### Development Setup

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Make your changes and add tests
4. Ensure tests pass: `bundle exec rspec`
5. Commit your changes: `git commit -m 'Add amazing feature'`
6. Push to the branch: `git push origin feature/amazing-feature`
7. Open a Pull Request

### Code Style

We use RuboCop for code style enforcement:

```bash
# Check code style
bundle exec rubocop

# Auto-fix issues
bundle exec rubocop -a
```

## 📋 Roadmap

### Version 1.1 (Next Release)
- [ ] SSO integrations (SAML, LDAP)
- [ ] Advanced audit analytics
- [ ] Webhook system
- [ ] API rate limiting
- [ ] Performance optimizations

### Version 1.2 (Future)
- [ ] Mobile SDK support
- [ ] Advanced MFA options (WebAuthn)
- [ ] Custom branding support
- [ ] Plugin architecture
- [ ] GraphQL API

## 📄 License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [DeviseTokenAuth](https://github.com/lynndylanhurley/devise_token_auth) for JWT authentication
- [Doorkeeper](https://github.com/doorkeeper-gem/doorkeeper) for OAuth 2.0 provider
- [ROTP](https://github.com/mdp/rotp) for TOTP implementation
- [RSwag](https://github.com/rswag/rswag) for API documentation

## 📞 Support & Community

### 📚 Documentation
- **[Complete Documentation Suite](#-documentation)** - All guides and references
- **[API Documentation](http://localhost:3001/api-docs)** - Interactive Swagger UI
- **[Integration Examples](docs/INTEGRATION_GUIDE.md)** - React, Vue, Node.js, Python examples
- **[Migration Guide](docs/MIGRATION_GUIDE.md)** - Upgrade from legacy authentication

### 🤝 Community
- **[GitHub Repository](https://github.com/EvolutionAPI/evo-auth-service)** - Source code and releases
- **[Issues](https://github.com/EvolutionAPI/evo-auth-service/issues)** - Bug reports and feature requests
- **[Discussions](https://github.com/EvolutionAPI/evo-auth-service/discussions)** - Community discussions and Q&A
- **[Releases](https://github.com/EvolutionAPI/evo-auth-service/releases)** - Latest versions and changelogs

### 📧 Contact
- **General**: [contato@evolution-api.com](mailto:contato@evolution-api.com)
- **Security**: [security@evolution-api.com](mailto:security@evolution-api.com)
- **Business**: [business@evolution-api.com](mailto:business@evolution-api.com)

---

<p align="center">
  <strong>Built with ❤️ by the Evolution Team</strong>
</p>

<p align="center">
  <a href="#-features">Features</a> •
  <a href="#-quick-start">Quick Start</a> •
  <a href="#-api-documentation">API Docs</a> •
  <a href="#-contributing">Contributing</a> •
  <a href="#-license">License</a>
</p>