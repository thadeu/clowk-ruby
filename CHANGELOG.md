# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.5.1] - 2026-08-04

### Fixed

- **API-only apps got a `302` instead of a `401`.** 0.5.0 decided a request was an API call by probing whether `session` was reachable, on the assumption that it raises without the session middleware. It does not: with no middleware loaded, `request.session` still returns an `ActionDispatch::Request::Session` that responds to `[]` and reads as `nil` — writes go nowhere, but nothing raises. So a real `ActionController::API` looked like a browser, and every unauthenticated call was answered with a redirect to a sign-in page the caller cannot follow. API mode is now detected from `ActionController::API` directly.
- The same mistake meant a bearer request in an API-only app still wrote a session and came back with `Set-Cookie`. It no longer does.

The 0.5.0 specs covered this with a dummy class whose `session` raised, which is not how Rails behaves — the tests passed against a model of the framework rather than the framework. Coverage now runs through a real `ActionController::API` in the test app; five of those seven examples fail against 0.5.0.

## [0.5.0] - 2026-08-04

### Security

- **Tokens are no longer verified with the signing secret.** `JwtVerifier` hardcoded `HS256` and checked signatures with `secret_key` — the same string the gem sends as an API credential in `X-Clowk-Secret-Key`. Any app holding its own key could therefore mint tokens it should only have been able to verify, and signing material travelled on the wire with every API call. `RS256` tokens are now verified against Clowk's published key set; the private half never leaves the auth server.
- **The `aud` claim is checked on `RS256` tokens.** Under a public key every consumer trusts, `aud` is the only thing keeping a token minted for one app out of another app's API — the per-instance shared secret used to prevent that by accident. `config.audience` defaults to `publishable_key`, so the check is on without extra configuration; set it to `false` or `nil` to skip it.

### Added

- `Clowk::Jwks` — fetches and caches Clowk's public keys. Verification must not cost a round trip, so the key set is cached process-wide; a `kid` the cache has not seen triggers a single refetch, which is what makes key rotation invisible rather than an outage. That refetch is throttled so a forged `kid` cannot turn one bad token into a stampede on the auth server, while a cold-cache fetch does not spend that budget — a rotation is still picked up on the very next token.
- `config.jwks_url` — where to fetch the key set. Defaults to `<auth domain>/.well-known/jwks.json`.
- `config.audience` — expected `aud` on `RS256` tokens. Defaults to `publishable_key`.
- `config.session_status_cache` — where API-only apps cache session status, keyed by a digest of the token so the raw token never lands somewhere loggable. Defaults to `Rails.cache`; set to `nil` to check with Clowk on every authenticated request.
- **API-only Rails support.** `Clowk::Authenticable` now works in `ActionController::API` controllers with no session or cookie middleware. `Clowk::Engine` hooks `:action_controller_api`, so `clowk_sign_in_path` exists on the unauthenticated path instead of raising `NoMethodError`.

### Fixed

- A bearer request no longer comes back with a `Set-Cookie`. `persist_clowk_session` wrote a session and a cookie on every successful verification, which raises without the middleware, is ignored by mobile clients, and defeats the point of a stateless API.
- API-only apps get `401` JSON on authentication failure regardless of the `Accept` header. The fallback previously keyed off `request.format.json?`, so an API call without an explicit `Accept` was answered with a `302` to a sign-in page the caller cannot use.
- `stored_session` returns `nil` rather than an empty hash when there is no session store. `nil.respond_to?(:to_h)` is true, so the old guard turned a missing store into a truthy value and every caller branching on "is there a session?" silently took the session path.

### Upgrading

Nothing to change for existing apps: `HS256` tokens still verify against `secret_key`, and `audience` is not enforced on that path because tokens issued before the claim existed do not carry it.

Two things matter once your Clowk server starts issuing `RS256`. Make sure `publishable_key` is configured — with only `secret_key` set, `audience` resolves to `nil` and the check is skipped, which fails open. And the gem must be able to reach the JWKS endpoint; set `jwks_url` explicitly if it is not derivable from `publishable_key` or `subdomain_url`.

`JwtVerifier::ALGORITHM` still exists as an alias of `LEGACY_ALGORITHM`, but it no longer describes what the verifier accepts.

## [0.4.1] - 2026-07-21

### Fixed

- `SDK::Resource#search` — and anything built on it, notably `subdomains.find_by_pk`, which resolves the instance URL from a `publishable_key` — raised `URI::InvalidComponentError`. `Http::Client#build_uri` assigned the whole `"resource/search?query=..."` string (query included) to `URI#path`, which rejects a `?`, and then dropped any query with `base_uri.query = nil`. The query is now split off and set as its own URI component, so search requests build a valid URL and keep their query. This path only ran when a domain was resolved from a publishable key rather than a configured `subdomain_url`, so it went unnoticed until then.

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
