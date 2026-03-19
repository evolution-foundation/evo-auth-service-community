# Changelog

All notable changes to EvoAuth Service will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- N/A

### Changed

- N/A

### Deprecated

- N/A

### Removed

- N/A

### Fixed

- N/A

### Security

- N/A

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
