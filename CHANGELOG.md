# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] - 2026-07-20

### Security

- **A token in the query string no longer establishes a session.** `TokenExtractor` read `params[:token]` on *every* request, and `Authenticable` persisted whatever verified — so `GET /anything?token=<valid jwt>` signed the visitor in as that token's subject, bypassing the OAuth callback's `state` check entirely. That is login-CSRF, and it left any token that reached a proxy log or browser history replayable for its full lifetime. Sessions are now established from the `Authorization: Bearer` header or the cookie only; `CallbacksController` still reads the param directly, after validating state.

### Fixed

- `clowk_enforce_session!` was a no-op after its first call. The fetched status was cached into the Rails session with no TTL and no timestamp, so every later call returned the stale cache and revocation was never noticed. Statuses now carry a `session_status_checked_at` stamp and expire — see `config.session_status_ttl` below.
- `config.enforce_active_session` was declared but never read anywhere: setting it did nothing. It now makes `authenticate_<prefix>!` verify session liveness (still defaulting to `false`, so existing behaviour is unchanged).
- `prefix_by` is honoured for sign-out. `clowk_sign_out!` kept its canonical name under every prefix, so `config.prefix_by = :user` gave you `current_user` and `authenticate_user!` but no `user_sign_out!`. The prefixed alias is now generated alongside the others.

### Added

- `config.session_status_ttl` (default `300`) — how long a fetched session status stays trusted, in seconds. Set `0` to check on every call.

### Upgrading

Breaking for anyone who authenticated by putting a token in a URL; use the `Authorization` header or let the callback set the cookie. If you set `enforce_active_session = true` expecting a no-op, it now costs one lookup per authentication, cached for `session_status_ttl`.

## [0.3.3] - 2026-06-21

### Fixed

- Use the valid SPDX identifier `AGPL-3.0-only` for the gemspec license (silences the `gem build` license warning)

## [0.3.2] - 2026-06-21

### Changed

- Automated gem publishing to RubyGems on `v*` tag pushes via GitHub Actions (verifies tag matches `Clowk::VERSION`, runs the suite, then builds and pushes)

## [0.3.1] - 2026-06-21

### Changed

- Replaced RuboCop with Standard (`standardrb`) for linting and CI

### Fixed

- `clowk_enforce_session!` no longer recurses infinitely under the default `:clowk` prefix (dynamic alias collided with the canonical method)
- `clowk_enforce_session!` now redirects to sign-in instead of raising a 500 when session verification fails (`resolve_session_status` rescues `InvalidTokenError`)
- `Session#search` once again accepts a positional raw query string, matching the base class signature

## [0.3.0] - 2026-06-21

### Changed

- Thread-safe Subdomain cache with Mutex
- Configurable `api_base_url` (defaults to `https://api.clowk.dev/api/v1`)
- `SDK::Client` uses `Clowk.config.api_base_url` instead of deriving from `subdomain_url`
- Overridable `clowk_handle_unauthenticated` and `clowk_handle_expired_session` methods
- CallbacksController uses generic flash messages (logs details server-side)
- `Token#verify_with_session` raises on error responses
- Configuration validates `secret_key`, `http_open_timeout`, `http_read_timeout`, and `http_write_timeout`
- `after_sign_in_path` and `after_sign_out_path` accept `Proc`/lambda values
- `clowk_authenticate!` always returns the current resource or raises

### Fixed

- LICENSE mismatch: README now correctly states AGPL-3.0
- `SDK::Client` ivar memoization uses singular class name consistently
- Removed unused `require 'cgi'` from url_helpers.rb
- Added `frozen_string_literal: true` to engine.rb
- `Response#to_h` key `:success?` normalized to `:success`
- Added `==`, `eql?`, `hash` to `Current` class

## [0.2.0] - 2026-05-15

### Added

- `Clowk::SDK::SessionConfig` resource for session configuration
- `Session#revoke` for revoking sessions by session_id
- `Token#verify_with_session` for combined token + session verification

### Changed

- `Session#search` now accepts keyword and raw query arguments (matching base class)

## [0.1.0] - 2026-03-22

### Added

- `Clowk::SDK::Client` as the main entry point for the Clowk API
- Resource-oriented API with `users`, `sessions`, `subdomains`, and `tokens`
- Zendesk-style search operators (`search(status: "active")` and raw string `search("field:value")`)
- `Clowk::SDK::Resource` base class with `list`, `find`, `show`, `search`, `destroy`
- `Clowk::SDK::Token#verify` for JWT token verification via API
- `Clowk::SDK::Subdomain#find_by_pk` for publishable key resolution
- `Clowk::Http` client built on `Net::HTTP` with middleware stack
- Retry middleware with configurable attempts and interval
- Timeout middleware with open, read, and write timeouts
- Logger middleware for request/response logging
- Response body size limit (1 MB default) to prevent OOM
- `Clowk::Http::Response` with hash-compatible interface
- `Clowk::Subdomain` for auth URL resolution with in-memory caching
- `Clowk::JwtVerifier` for HS256 JWT verification
- `Clowk::Authenticable` concern for Rails controllers
- URL helpers for sign in, sign up, and sign out
- Rails Engine with callback and session routes
- Token extraction from params, cookies, and Authorization header
- Custom exceptions: `ConfigurationError`, `InvalidStateError`, `InvalidTokenError`
- GitHub Actions CI with Ruby 3.3 and 3.4
