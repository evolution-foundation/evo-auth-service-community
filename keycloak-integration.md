# Keycloak Integration

## Overview

This document describes the Keycloak SSO (Single Sign-On) integration for the Evo Auth Service. The integration enables users to authenticate through a centralized Keycloak identity provider, supporting OAuth2/OIDC flows with PKCE (Proof Key for Code Exchange) for enhanced security.

## Features

- **SSO Authentication**: Users can authenticate via Keycloak using OAuth2/OIDC
- **PKCE Flow**: Supported and recommended, but optional — flows without PKCE are accepted (e.g. confidential clients)
- **JWT Validation**: Validates Keycloak-issued JWTs against the realm's JWKS endpoint
- **JIT User Provisioning**: Just-In-Time user creation and role synchronization
- **Role Synchronization**: Syncs user roles from Keycloak claims to local roles
- **Logout Support**: Proper Keycloak session termination with redirect

## Required Environment Variables

### Essential Variables (Required)

| Variable | Description | Example |
|----------|-------------|---------|
| `KEYCLOAK_ENABLED` | Enable Keycloak integration | `true` |
| `KEYCLOAK_ISSUER` | JWT issuer / public realm URL | `https://keycloak.example.com/realms/organization` |
| `KEYCLOAK_CLIENT_ID` | Public client ID registered in Keycloak | `evo-auth-client` |

### Optional Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `KEYCLOAK_INTERNAL_URL` | Internal Docker URL for HTTP calls (falls back to KEYCLOAK_ISSUER) | `KEYCLOAK_ISSUER` value |
| `KEYCLOAK_SSL_VERIFY` | Set to `false` in development to skip SSL verification | `true` |
| `KEYCLOAK_ROLES_CLAIM` | JWT claim path for realm roles | `realm_access.roles` |
| `FRONTEND_URL` | Frontend URL for post-logout redirects | `http://localhost:5173` |

## Authentication Flow

```
┌─────────────┐                                    ┌─────────────┐
│   Frontend  │                                    │  Keycloak   │
└──────┬──────┘                                    └──────┬──────┘
       │                                                  │
       │ 1. User clicks "Login with Keycloak"             │
       │                                                  │
       │ 2. Frontend generates PKCE code_verifier         │
       │    and redirects to Keycloak authorize endpoint    │
       │───────────────────────────────────────────────────>│
       │                                                  │
       │ 3. User authenticates in Keycloak                  │
       │    Keycloak redirects back with authorization code│
       │<───────────────────────────────────────────────────│
       │                                                  │
       │ 4. Frontend sends code + code_verifier           │
       │    to backend /api/v1/auth/keycloak_exchange       │
       │───────────────────────────────────────────────────>│
       │                                ┌───────────────────┐
       │                                │   Evo Auth        │
       │                                │   Service         │
       │                                └─────────┬─────────┘
       │                                          │
       │                                          │ 5. Exchange code
       │                                          │    for tokens with
       │                                          │    Keycloak token endpoint
       │                                          │─────────────────────>│
       │                                          │                      │
       │                                          │ 6. Keycloak returns
       │                                          │    access_token + id_token
       │                                          │<─────────────────────│
       │                                          │
       │                                          │ 7. Validate JWT against
       │                                          │    JWKS endpoint
       │                                          │─────────────────────>│
       │                                          │<─────────────────────│
       │                                          │
       │                                          │ 8. Provision/Update user
       │                                          │    Sync roles from claims
       │                                          │
       │ 9. Return Evo OAuth tokens               │
       │<─────────────────────────────────────────│
       │                                          │
```

## API Endpoints

### Keycloak Exchange

**Endpoint**: `POST /api/v1/auth/keycloak_exchange`

Exchanges a Keycloak authorization code or token for Evo Auth Service tokens.

**Request Body (PKCE Flow — recommended)**:
```json
{
  "code": "authorization_code_from_keycloak",
  "code_verifier": "pkce_code_verifier_generated_by_frontend",
  "redirect_uri": "http://localhost:5173/auth/callback"
}
```

**Request Body (Without PKCE — accepted but logs a security warning)**:
```json
{
  "code": "authorization_code_from_keycloak",
  "redirect_uri": "http://localhost:5173/auth/callback"
}
```

**Request Body (Direct Token)**:
```json
{
  "keycloak_token": "keycloak_access_token_jwt"
}
```

**Success Response**:
```json
{
  "data": {
    "user": {
      "id": 123,
      "email": "user@example.com",
      "name": "John Doe",
      "role": "admin"
    },
    "access_token": "evo_access_token",
    "refresh_token": "evo_refresh_token",
    "expires_in": 7200,
    "token_type": "Bearer"
  },
  "message": "Login successful"
}
```

**Error Responses**:
- `501 Not Implemented` - Keycloak not enabled (`KEYCLOAK_ENABLED` not set)
- `400 Bad Request` - Missing code or keycloak_token
- `401 Unauthorized` - Invalid or expired token
- `502 Bad Gateway` - Token exchange with Keycloak failed
- `422 Unprocessable Entity` - User creation/validation failed

### Keycloak Token Refresh

**Endpoint**: `POST /api/v1/auth/keycloak_refresh`

Renews the Keycloak session using the `refresh_token` stored during the last exchange. Re-provisions/updates the user and issues new Evo tokens.

**Request Body**:
```json
{
  "keycloak_refresh_token": "kc_refresh_token_stored_from_exchange"
}
```

**Success Response**: identical to `keycloak_exchange`.

**Error Responses**:
- `501 Not Implemented` - Keycloak not enabled
- `400 Bad Request` - `keycloak_refresh_token` missing
- `401 Unauthorized` - refresh token expired (`REFRESH_TOKEN_EXPIRED`) or new JWT invalid
- `502 Bad Gateway` - communication error with Keycloak

> **Future improvement**: the refresh logic could be extracted into a `before_action` (e.g. `refresh_keycloak_session_if_needed`) that transparently renews the Keycloak session whenever the stored Evo access token is near expiry. This would allow clients to remain authenticated without explicitly calling `keycloak_refresh`, mirroring silent refresh patterns common in OIDC.

### Logout with Keycloak

When a user authenticated via Keycloak logs out, the response includes a Keycloak logout URL:

**Endpoint**: `POST /api/v1/auth/logout`

**Response**:
```json
{
  "data": {
    "keycloak_logout_url": "https://keycloak.example.com/realms/organization/protocol/openid-connect/logout?id_token_hint=...&post_logout_redirect_uri=...&client_id=..."
  },
  "message": "Logged out successfully"
}
```

The frontend should redirect the user to this URL to properly terminate the Keycloak session.

## Components

### 1. CodeExchanger (`lib/keycloak/code_exchanger.rb`)

Exchanges PKCE authorization code for Keycloak access token server-side.

**Usage**:
```ruby
tokens = Keycloak::CodeExchanger.exchange(
  code: params[:code],
  code_verifier: params[:code_verifier],
  redirect_uri: params[:redirect_uri]
)
# Returns: { access_token: "...", id_token: "..." }
```

**Configuration**:
- `KEYCLOAK_ISSUER` - Base URL for token endpoint
- `KEYCLOAK_CLIENT_ID` - Client identifier
- `KEYCLOAK_SSL_VERIFY` - SSL verification mode

### 2. JwtValidator (`lib/keycloak/jwt_validator.rb`)

Validates Keycloak-issued JWTs against the realm's JWKS endpoint with caching.

**Usage**:
```ruby
claims = Keycloak::JwtValidator.verify(raw_token)
# Returns: Hash of JWT claims or raises Keycloak::JwtValidator::Error
```

**Features**:
- JWKS caching (300 seconds TTL)
- Thread-safe cache with mutex
- Supports multiple accepted issuers (public + internal)
- RSA signature verification (RS256, RS384, RS512)

### 3. UserProvisioner (`lib/keycloak/user_provisioner.rb`)

Handles JIT user provisioning and role synchronization from Keycloak claims.

**Usage**:
```ruby
user = Keycloak::UserProvisioner.provision!(claims)
```

**Features**:
- Looks up users by `keycloak_sub` (preferred) or `email`
- Creates new users with provider="keycloak" if not found
- Syncs roles from JWT claims (realm and client roles)
- Full role synchronization (Keycloak is source of truth)

**Role Extraction**:
- Realm roles: From claim path defined by `KEYCLOAK_ROLES_CLAIM` (default: `realm_access.roles`)
- Client roles: From `resource_access.{client_id}.roles`

### 4. LogoutUrl (`lib/keycloak/logout_url.rb`)

Builds Keycloak logout URL for session termination.

**Usage**:
```ruby
url = Keycloak::LogoutUrl.build(
  id_token_hint: user.keycloak_id_token,
  post_logout_redirect_uri: "#{frontend_url}/login"
)
```

## Role Synchronization

### Creating Roles from Keycloak

A rake task is available to create Evolution roles from Keycloak role keys:

```bash
# Create roles with agent permissions
docker compose exec evo_auth bundle exec rails keycloak:create_roles ROLES="realm_role"

# Create account-level roles
docker compose exec evo_auth bundle exec rails keycloak:create_roles ROLES="client_role" ROLE_TYPE="account"
```

The task:
1. Creates roles with the specified keys
2. Seeds them with permissions from the 'agent' role
3. Sets proper naming and descriptions

### Role Mapping

Keycloak roles are mapped to local roles by matching the role key:

| Keycloak Role | Evolution Role |
|---------------|----------------|
| `admin` | `admin` |
| `supervisor` | `supervisor` |
| `agent` | `agent` |

The system reads roles from:
1. `realm_access.roles` claim (configurable via `KEYCLOAK_ROLES_CLAIM`)
2. `resource_access.{client_id}.roles` claim

## Database Schema

The following columns track Keycloak integration:

```ruby
# db/migrate/20260609200000_add_keycloak_sub_to_users.rb
add_column :users, :keycloak_sub, :string
add_index :users, :keycloak_sub, unique: true, where: "keycloak_sub IS NOT NULL"

# db/migrate/20260609100000_add_keycloak_id_token_to_users.rb
add_column :users, :keycloak_id_token, :text

# db/migrate/20260618000000_add_keycloak_refresh_token_to_users.rb
add_column :users, :keycloak_refresh_token, :text
add_column :users, :keycloak_refresh_token_expires_at, :datetime
```

- `keycloak_sub` - Keycloak subject identifier (unique per user in realm)
- `keycloak_id_token` - Cached ID token for logout
- `keycloak_refresh_token` - Keycloak refresh token for session renewal via `keycloak_refresh`
- `keycloak_refresh_token_expires_at` - Expiration datetime of the stored refresh token

## Configuration Example

### Development

```env
KEYCLOAK_ENABLED=true
KEYCLOAK_ISSUER=http://localhost:8080/realms/organization
KEYCLOAK_CLIENT_ID=evo-auth-client
KEYCLOAK_SSL_VERIFY=false
KEYCLOAK_ROLES_CLAIM=realm_access.roles
FRONTEND_URL=http://localhost:5173
```

### Production

```env
KEYCLOAK_ENABLED=true
KEYCLOAK_ISSUER=https://keycloak.example.com/realms/organization
KEYCLOAK_INTERNAL_URL=http://keycloak:8080/realms/organization
KEYCLOAK_CLIENT_ID=evo-auth-client
KEYCLOAK_SSL_VERIFY=true
KEYCLOAK_ROLES_CLAIM=realm_access.roles
FRONTEND_URL=https://app.example.com
```

## Keycloak Client Configuration

### Required Settings

1. **Client Protocol**: `openid-connect`
2. **Client Authentication**: OFF (public client for PKCE)
3. **Authorization**: OFF
4. **Standard Flow**: ON
5. **Direct Access Grants**: OFF (PKCE only)
6. **Implicit Flow**: OFF

### Valid Redirect URIs

Add your frontend callback URLs:
- `http://localhost:5173/*` (development)
- `https://app.example.com/*` (production)

### Web Origins

Configure CORS origins:
- `http://localhost:5173`
- `https://app.example.com`

### Mappers (Optional)

To include realm roles in the token:
1. Go to Client Scopes > roles > Mappers
2. Add "realm roles" mapper
3. Set token claim name: `realm_access.roles`

## Security Considerations

1. **PKCE Flow**: Recommended for public clients; omitting `code_verifier` logs a security warning but is not blocked
2. **Server-Side Exchange**: Authorization code is exchanged server-side, never in browser
3. **JWKS Validation**: All tokens are validated against Keycloak's JWKS endpoint
4. **Issuer & Expiration**: `iss`, `exp`, and `nbf` claims are verified explicitly with descriptive error messages
5. **Supported Algorithms**: RS256, RS384, RS512 (RSA family only — HMAC not supported for third-party tokens)
6. **SSL Verification**: Enable in production (`KEYCLOAK_SSL_VERIFY=true`)
7. **Token Storage**: ID tokens and Keycloak refresh tokens are stored in the database
8. **Token/Cookie Handling**: Managed server-side via HttpOnly cookies — the frontend must NOT handle tokens directly (BFF pattern)

## Troubleshooting

### JWKS Fetch Failures

Check `KEYCLOAK_INTERNAL_URL` is accessible from the backend. Common issues:
- Docker network connectivity
- SSL certificate validation (set `KEYCLOAK_SSL_VERIFY=false` for self-signed certs in dev)

### Role Sync Issues

Verify `KEYCLOAK_ROLES_CLAIM` matches your Keycloak token structure. Check logs for:
```
[Keycloak::UserProvisioner] realm claim=realm_access.roles roles=[...]
```

### Token Exchange Failures

Check the Keycloak client configuration:
- Client must be public (no secret)
- PKCE must be enabled
- Redirect URI must match exactly

## Related Files

- `lib/keycloak/code_exchanger.rb` - Token exchange (PKCE optional)
- `lib/keycloak/jwt_validator.rb` - JWT validation (RS256/384/512, issuer, exp, nbf)
- `lib/keycloak/token_refresher.rb` - Keycloak session refresh
- `lib/keycloak/user_provisioner.rb` - User provisioning and role sync
- `lib/keycloak/logout_url.rb` - Logout URL builder
- `app/controllers/api/v1/auth_controller.rb` - API endpoints
- `lib/tasks/keycloak_roles.rake` - Role creation task
- `spec/lib/keycloak/jwt_validator_spec.rb` - Unit tests: JWT validation
- `spec/lib/keycloak/code_exchanger_spec.rb` - Unit tests: code exchange
- `spec/lib/keycloak/token_refresher_spec.rb` - Unit tests: token refresh
- `spec/lib/keycloak/user_provisioner_spec.rb` - Unit tests: user provisioning
- `spec/requests/api/v1/keycloak_spec.rb` - Integration tests: endpoints
