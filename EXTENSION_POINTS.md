# Extension Points

Each extension point below is versioned independently under SemVer; see
the [Compatibility Promise](#compatibility-promise) and the per-EP
`Version` lines. The document itself is not versioned — there is no
single aggregate "contract version".

This document is the public contract between `evo-auth-service-community`
and any external consumer that wants to plug into authentication without
forking or patching community source. The authoritative architectural
decision behind this contract is **ADR13 — Extension Points Versioning
Strategy**; the rules below are self-contained.

The community release is fully usable on its own. Every extension point
ships with a working default that delegates to the in-tree Devise /
devise_token_auth stack; a consumer can **replace** the default
implementation of one or more of them without modifying files in `app/`,
`lib/` or `db/`.

If you are about to change any of the extension points below, read
the [Compatibility Promise](#compatibility-promise) first.

---

## Compatibility Promise

Each extension point is versioned independently and treated as a public
API, with the same backward-compatibility rules as the REST endpoints
exposed by this service:

- **Backward compatibility is forever.** Once shipped at a given major,
  the name, arguments, return shape and observable behavior of an
  extension point do not change silently.
- **Breaking changes require a major bump** of the affected extension
  point and of the community release that ships it.
- **Deprecation window is at least one minor release.** The old shape
  keeps working alongside the new one, and the deprecated path emits a
  warning via `Rails.logger`.
- **Additive changes are minor bumps.** New extension point, or new
  optional capability on an existing one.
- **Bug fixes that preserve the contract are patch bumps.**

Bumping one extension point does not bump the others.

---

## Registration API

**Version:** `1.0.0`

The registration mechanism is itself part of the public contract. Every
override goes through one method:

```ruby
EvoExtensionPoints.replace(name) { |*args, **kwargs| ... }
```

**Accepted `name` values:** `:auth_bridge_create_user`,
`:auth_bridge_find_user_by_email` (v1.1.0+),
`:auth_bridge_sign_in_user`, `:auth_bridge_sign_in_request` (v1.1.0+),
`:auth_bridge_current_user`, `:auth_bridge_sign_out`, `:token_claims`,
`:login_gate`, `:after_bootstrap`, `:extra_setup_steps`. Adding a new
accepted name is a minor bump; removing or renaming an accepted name is
a major bump.

**Block contract:** the block is called with the arguments documented
for each extension point. The auth-service verifies the block's arity
at registration time against the expected shape; a block whose arity
cannot satisfy the EP signature raises `ArgumentError` synchronously.

**Idempotency / replacement order:** `replace` is last-write-wins.
Each call replaces the previously registered block atomically. The
returned value is `nil`; callers that need the previous block must
capture it before calling `replace`.

**When it may be called:** any time before the first call site that
exercises the extension point. The recommended placement is a
`Rails::Railtie` / `Rails::Engine` `initializer`, before the app
finishes booting. Calling `replace` after the EP has been exercised
is allowed and atomic, but in-flight calls observe the previous block.

**Thread safety:** `replace` is safe to call from any thread. Reads
of the active block are lock-free.

**Failure modes:**
- Unknown `name` → `KeyError`.
- Block missing or with incompatible arity → `ArgumentError`.

A complementary helper, `EvoExtensionPoints.reset(name)`, restores the
community default for a given extension point. Calling `reset` with an
unknown name raises `KeyError`.

---

## Extension points

All are exposed under the `EvoExtensionPoints` namespace,
implemented by `lib/evo_extension_points/` (shipped in a complementary
story). Each extension point exposes its own version as
`EvoExtensionPoints::<EP>::VERSION` (e.g.
`EvoExtensionPoints::AuthBridge::VERSION == "1.0.0"`); there is no
aggregate `EXTENSION_POINTS_VERSION` constant — version each EP
independently.

### 1. `auth_bridge`

**Version:** `1.1.0`
**Default:** delegates to the in-tree Devise / devise_token_auth stack;
`current_user` returns the user resolved by `devise_token_auth` from the
current request, or `nil` outside a request scope.

```ruby
EvoExtensionPoints::AuthBridge.create_user(email:, password:, attrs: {}) # => User
EvoExtensionPoints::AuthBridge.find_user_by_email(email)                 # => User | nil   (v1.1.0+)
EvoExtensionPoints::AuthBridge.sign_in_user(user)                        # => user signed in for the current request
EvoExtensionPoints::AuthBridge.sign_in_request(user, request)            # => user bound to request (Warden); v1.1.0+
EvoExtensionPoints::AuthBridge.current_user                              # => User | nil
EvoExtensionPoints::AuthBridge.sign_out(user)                            # => user signed out
```

`find_user_by_email` lets a consumer look up an existing user by email
without touching `User` directly. Returns `nil` when no row matches.

`sign_in_request` binds `user` to the request's Warden proxy so the next
request — typically after a redirect — sees them as authenticated.
`sign_in_user` only carries the user through `ActiveSupport::Current`
inside the live request and does not survive a redirect; flows that
need post-redirect authentication MUST use `sign_in_request` instead.

Override:

```ruby
EvoExtensionPoints.replace(:auth_bridge_create_user) do |email:, password:, attrs: {}|
  MyConsumer::Accounts.create_user(email: email, password: password, attrs: attrs)
end

EvoExtensionPoints.replace(:auth_bridge_find_user_by_email) { |email| MyConsumer::Users.find_by_email(email) }
EvoExtensionPoints.replace(:auth_bridge_sign_in_user)       { |user| MyConsumer::Sessions.sign_in(user) }
EvoExtensionPoints.replace(:auth_bridge_sign_in_request)    { |user, request| MyConsumer::Sessions.bind(user, request) }
EvoExtensionPoints.replace(:auth_bridge_current_user)       { MyConsumer::Current.user }
EvoExtensionPoints.replace(:auth_bridge_sign_out)           { |user| MyConsumer::Sessions.sign_out(user) }
```

**Breaking-change policy:** renaming `create_user`, `find_user_by_email`,
`sign_in_user`, `sign_in_request`, `current_user` or `sign_out`,
changing required keyword arguments, or changing the return type of
`current_user` from `User | nil` is a major bump. Adding an optional
keyword argument to `create_user` or sibling helpers is a minor bump.

### 2. `token_claims`

**Version:** `1.0.0`
**Default:** returns an empty hash; the community release adds no extra
claims beyond what devise_token_auth already emits.

```ruby
EvoExtensionPoints::TokenClaims.claims_for(user) # => Hash<String, Object>
```

Override:

```ruby
EvoExtensionPoints.replace(:token_claims) do |user|
  MyConsumer::Claims.for(user) # e.g. { "audience" => "my_consumer", "roles" => user.role_names }
end
```

The returned hash is merged into the token payload by the auth-service
at emission time. Keys reserved by the JWT spec (`iss`, `sub`, `aud`,
`exp`, `iat`, `nbf`, `jti`) MUST NOT be overwritten by a consumer.

**Collision handling — strict at v1.0.0:**

- **Production / staging** (`Rails.env.production? || Rails.env.staging?`):
  the conflicting reserved keys are dropped from the consumer hash and
  the auth-service logs at `ERROR` with the offending key list, the
  consumer-supplied value (truncated), and the calling override name.
  Token emission proceeds with the auth-service-owned values.
- **Development / test:** the same merge raises
  `EvoExtensionPoints::TokenClaims::ReservedKeyError` synchronously so
  the violation is caught in CI before it reaches production.

Non-reserved keys returned by the consumer are merged as-is. If the
consumer hash includes a key that the auth-service later adds to the
reserved set (a minor bump), the same drop-and-log behavior applies —
not a silent overwrite of consumer data.

**Breaking-change policy:** renaming `claims_for`, changing the return
type from `Hash`, or silently overwriting reserved JWT keys is a major
bump. Adding new optional behavior on top of the merge is a minor bump.

### 3. `login_gate`

**Version:** `1.0.0`
**Default:** always returns `:allow`; the community release performs no
pre-login check beyond what Devise already enforces (confirmed,
not-locked, valid credentials).

```ruby
EvoExtensionPoints::LoginGate.check(user, **context) # => :allow | [:deny, reason]
```

`context` carries neutral request-derived data (e.g. `ip:`,
`user_agent:`) that the consumer may use to decide.

**Accepted return shapes (v1.0.0) — strict:**

| Return value | Meaning |
|---|---|
| `:allow` | Login proceeds. |
| `[:deny, reason]` where `reason` is a `Symbol` | Login is denied. `reason` (e.g. `:rate_limited`, `:not_active`) is recorded in the audit log; the end user sees only the generic "login failed" copy returned by Devise. |

**Any other return value is a contract violation.** The auth-service
raises `EvoExtensionPoints::LoginGate::InvalidReturnError` and
**denies the login** (fail-closed). The offending return value and the
calling consumer are recorded in the audit log so the override can be
fixed. `nil`, `true`, `false`, strings and missing returns are all
treated as violations — none of them silently allow or silently deny.

**Exceptions raised by the override** are caught by the auth-service,
logged at `ERROR` with the backtrace, and **deny the login**
(fail-closed). The audit log entry records `denial_reason:
:gate_exception` plus the exception class. The end user sees only the
generic "login failed" copy. Re-raising upstream is not done because
that would surface internal-consumer errors to the end user.

Override:

```ruby
EvoExtensionPoints.replace(:login_gate) do |user, **context|
  MyConsumer::Access.check(user, **context)
end
```

**Breaking-change policy:** renaming `check`, narrowing or extending
the set of accepted return shapes (e.g. accepting `true` for allow),
or changing the fail-closed default for unknown returns / exceptions
is a major bump. Adding new accepted keys in `context` or new accepted
denial reasons is a minor bump.

### 4. `after_bootstrap`

**Version:** `1.0.0`
**Default:** no-op; a pure community install runs no side effect after the
first admin user is created.

```ruby
EvoExtensionPoints::AfterBootstrap.run(user:, payload:) # => nil
```

Dispatched **inside** the `/setup` bootstrap transaction, immediately after
the first admin `user` and its global role are created. `payload` is an
**opaque** hash forwarded verbatim from the request's `extension_payload`; the
community assigns it no meaning, and the consumer validates and interprets it.

> ⚠️ **Security:** `payload` arrives **fully unfiltered** — the community
> `permit!`s the request bag and forwards it as-is, performing no allow-listing.
> A consumer MUST `permit` / validate every key before using it in any
> mass-assignment or SQL write; treat it as untrusted end-user input.

**Error policy — no rescue (fail-through):** the dispatcher does NOT rescue.
Because the call site is inside the bootstrap transaction, an exception raised
by the consumer block rolls the **whole install** back — atomicity is the
feature. The consumer owns any internal fail-open / fail-closed policy.

Override:

```ruby
EvoExtensionPoints.replace(:after_bootstrap) do |user:, payload:|
  MyConsumer::Bootstrap.after(user: user, payload: payload)
end
```

**Breaking-change policy:** renaming `run`, changing the `user:` / `payload:`
keyword shape, moving the call site outside the bootstrap transaction, or
changing the no-rescue policy is a major bump. Adding an optional keyword is a
minor bump.

### 5. `extra_setup_steps`

**Version:** `1.0.0`
**Default:** returns `false`; a pure community install has a single-step Setup
wizard.

```ruby
EvoExtensionPoints::ExtraSetupSteps.enabled? # => Boolean
```

Backs the `extra_setup_steps` boolean on `GET /setup/status`, telling the
frontend Setup wizard whether a registered consumer contributes extra steps
after the account step.

**Error policy — fail-soft:** any exception raised by the consumer block is
caught, logged at `WARN`, and degrades to `false` so a broken probe never traps
the user on `/setup`.

Override:

```ruby
EvoExtensionPoints.replace(:extra_setup_steps) { true }
```

**Breaking-change policy:** renaming `enabled?`, changing the return type from
`Boolean`, or changing the fail-soft default is a major bump.

---

## How to use as a consumer

A consumer wires its replacements once, from a `Railtie` or `Engine`
initializer, and never patches files inside `evo-auth-service-community`:

```ruby
require "evo_extension_points"

module MyConsumer
  class Railtie < ::Rails::Railtie
    initializer "my_consumer.auth_extension_points" do
      EvoExtensionPoints.replace(:auth_bridge_create_user) do |email:, password:, attrs: {}|
        MyConsumer::Accounts.create_user(email: email, password: password, attrs: attrs)
      end

      EvoExtensionPoints.replace(:auth_bridge_current_user) { MyConsumer::Current.user }

      EvoExtensionPoints.replace(:token_claims) do |user|
        { "audience" => "my_consumer", "roles" => user.role_names }
      end

      EvoExtensionPoints.replace(:login_gate) do |user, **context|
        MyConsumer::Access.check(user, **context)
      end
    end
  end
end
```

A consumer is expected to declare the community version range it
supports in its own package metadata (gemspec). A future CI workflow
(`extension-points-contract`) will run a neutral consumer stub against
every community PR and fail the build on a contract break; until that
workflow lands, contract regressions are caught by manual review of
changes to this file and the `lib/evo_extension_points/`
implementation.

---

## Cross-references

- Companion contract on the CRM side:
  [evo-ai-crm-community/EXTENSION_POINTS.md](https://github.com/evolution-foundation/evo-ai-crm-community/blob/main/EXTENSION_POINTS.md).
- Companion contract on the Python processor side:
  [evo-ai-processor-community/EXTENSION_POINTS.md](https://github.com/evolution-foundation/evo-ai-processor-community/blob/main/EXTENSION_POINTS.md).
- The architectural decision that motivates this contract is **ADR13 —
  Extension Points Versioning Strategy**.

---

## Versioning history

Each line below tracks one independently versioned surface. The
document itself is unversioned.

- Registration API `1.0.0` — Initial: `replace(name) { ... }` +
  `reset(name)`.
- `auth_bridge` `1.0.0` — Initial contract.
- `auth_bridge` `1.1.0` — Additive: `find_user_by_email(email)` for
  email-based user lookup without touching `User`, and
  `sign_in_request(user, request)` to bind a user to the request's
  Warden proxy so authentication survives a redirect. New registration
  keys: `:auth_bridge_find_user_by_email` and
  `:auth_bridge_sign_in_request`.
- `token_claims` `1.0.0` — Initial contract.
- `login_gate` `1.0.0` — Initial contract.
- `after_bootstrap` `1.0.0` — Initial: no-op hook dispatched inside the
  `/setup` bootstrap transaction with `(user:, payload:)`; no rescue, so a
  consumer exception rolls the install back. New registration key:
  `:after_bootstrap`.
- `extra_setup_steps` `1.0.0` — Initial: fail-soft capability query backing
  the `extra_setup_steps` boolean on `GET /setup/status`; default false. New
  registration key: `:extra_setup_steps`.
