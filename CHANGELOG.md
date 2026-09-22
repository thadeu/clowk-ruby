# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.10.0] - 2026-09-21

### Changed

- **`token_store` no longer mirrors the token into the app's session by default, and `:clowk` is
  gone — the value is `nil` or `:app`.** Clowk writes its own cookie whatever the setting says, so
  the only question the setting ever answered was whether a COPY also goes into the host app's
  Rails session. `nil` says no, `:app` says yes, and nothing else is a valid value.

  ```ruby
  config.token_store = nil   # Clowk's own cookie, and nowhere else (the default)
  config.token_store = :app  # also mirrored into the app's Rails session
  ```

  The copy was the default for every version up to 0.9.1, and it is the one that can break an app
  in silence: a Rails session is ONE cookie of about 4096 bytes, an RS256 token is most of what one
  weighs, and a browser handed more than it will hold discards the whole cookie without a word —
  flash message, selected tenant, CSRF rotation and all. An app should not pay that on every
  request to keep a second copy of a token Clowk's own cookie already carries.

### Upgrading

Most apps do nothing. `current_token`, `current_clowk` and `clowk_signed_in?` read the same values
as before, and sessions written under the old default are pruned on their next request.

An app that reads the token out of `session[...]` itself, rather than through `current_token`, must
ask for the copy:

```ruby
Clowk.configure { |config| config.token_store = :app }
```

An app already on `:clowk` (0.9.x only) changes that value to `nil`, or removes the line.

## [0.9.1] - 2026-09-21

### Changed

- **`token_store` takes `:app` or `:clowk`, not `:session` or `:cookie`.** Both stores ARE cookies
  — the Rails session is one cookie carrying everything the app puts in `session[...]`, and Clowk's
  is another — so naming them after the mechanism said nothing. The setting names the owner now,
  which is the thing that actually differs.

  ```ruby
  config.token_store = :clowk  # was :cookie
  config.token_store = :app    # was :session, still the default
  ```

  0.9.0 was published minutes earlier and is the only version that ever used the old names.

## [0.9.0] - 2026-09-21

### Added

- **`config.token_store`** — `:session` (the default, and what every version before this did) or
  `:cookie`. Clowk's own cookie is written either way; the setting decides whether a copy is also
  mirrored into the app's Rails session.

  The copy is not free. A Rails session lives in one cookie with about 4096 bytes to its name, and
  in production, where tokens are RS256, the token is most of what a session weighs. Hand a browser
  more than it will hold and it discards the whole cookie **in silence** — no exception
  server-side, nothing in the console, the previous cookie simply stays. Everything written on that
  request goes with it: a flash message, a selected tenant, a CSRF rotation. What a person sees is a
  button that does nothing, and what the log shows is a request that succeeded.

  Under `:cookie` the session keeps the claims and the sign-in time and nothing else, which is
  roughly a third of what it held. `current_token` reads Clowk's cookie instead — the path an
  API-only app has always taken. Sessions written before the switch are pruned on their next
  request, so an app does not have to wait for everyone to sign out and back in.

### Upgrading

Nothing changes. `:session` is the default, so an app behaves exactly as it did until it asks for
`:cookie`.

An app whose session cookie is anywhere near 4096 bytes should ask:

```ruby
Clowk.configure { |config| config.token_store = :cookie }
```

## [0.8.0] - 2026-09-21

### Changed

- **`clowk_require_fresh_session` is gone; use `before_action :clowk_enforce_fresh_session!`.**
  The class macro was the odd one out — everything else the concern gives a controller is an
  instance method, named for `prefix_by` and used as an ordinary filter. One shape is easier to
  remember than two, and a plain `before_action` carries every filter option without the macro
  having to pass them through.

  ```ruby
  # before
  clowk_require_fresh_session only: [:create, :destroy]

  # after
  before_action :clowk_enforce_fresh_session!, only: [:create, :destroy]

  # or, under prefix_by = :clowk_user
  before_action :clowk_user_enforce_fresh_session!, only: [:create, :destroy]
  ```

  The method itself is unchanged, and has carried the scoped name since 0.7.0 — only the macro
  around it is removed.

## [0.7.1] - 2026-09-21

### Fixed

- **`clowk_enforce_session!` no longer expires a session that never existed.** Reached through
  `clowk_authenticate!` it is always preceded by a signed-in check, but it is also usable as a
  `before_action` on its own — which is how an app runs the freshness check on its own terms. Called
  that way with no session it read "not active" and took the expiry route, signing out nobody and
  redirecting.

  On a page that skips the identity gate deliberately — an invite link, a public page that shows
  more once you are signed in — that replaced a redirect carrying `return_to` with a bare one, so
  the visitor signed in and landed somewhere other than the link they followed.

  It now returns early when nobody is signed in. There is nothing to enforce against an anonymous
  request, and `clowk_authenticate!` still refuses it as before.

## [0.7.0] - 2026-09-21

### Added

- **`clowk_require_fresh_session`** — a controller macro that demands a live answer from Clowk
  before the actions it names, whatever a cached status says.

  ```ruby
  class ApiKeysController < ApplicationController
    clowk_require_fresh_session only: [:create, :update, :destroy]
  end
  ```

  It takes the same options as `before_action`. Everything not named keeps the cached check, which
  is the point: an app pays for a round trip on the few actions it cannot undo, and nowhere else.
  `clowk_enforce_fresh_session!` is the same thing as a method, and `clowk_session_status` /
  `clowk_session_active?` now take `force:` for callers that want the answer rather than the
  enforcement.

  Until now there was no way to bypass the cache for one call, so an app that needed a genuinely
  fresh check anywhere had to set `session_status_ttl = 0` and pay a round trip on every page — or
  rebuild the whole cadence itself, which is what the one app that needed it did.

- **`config.max_session_age`** — a local ceiling, in seconds, that Clowk plays no part in. Past it
  the session ends without a round trip. `nil` (the default) leaves Clowk as the only authority.
  It is the other half of failing open: without a ceiling, a permanently unreachable broker means a
  session that never ends.

- **`config.fail_open_on_broker_error`** (default `true`) — when the liveness check cannot be made
  at all, the session is left standing and checked again on the next request. A blip on the way to
  a single droplet must not sign everyone out. Only network failures count; anything else still
  raises, because a bug must not read as "the session is probably fine". Set it to `false` to fail
  closed.

### Changed

- Expiry now takes one route, whichever end it came from — the broker said inactive, or the local
  ceiling passed. `config.on_session_expired` sees both.

### Upgrading

Nothing to change. The new settings are off or default to today's behaviour, and the existing
methods keep their signatures.

An app that set `session_status_ttl = 0` to guarantee freshness can now give the ordinary check a
real TTL and mark the handful of actions that need more:

```ruby
config.session_status_ttl = 15.minutes
config.max_session_age = 12.hours
```

## [0.6.1] - 2026-09-21

### Fixed

- **A `session_status_ttl` of zero no longer writes to the session.** The guard that skips caching
  sat below the session branch and covered only the external cache, so an app that set the TTL to
  zero — the one way to guarantee a genuinely fresh check before a destructive action, since there
  is no way to bypass the cache for a single call — still had the full status payload merged into
  its Rails session on every request, and never read back: `clowk_session_status_fresh?` returns
  false without a positive TTL, so the write was never once used.

  In a cookie session that is write-only weight in 4096 bytes, growing with the status payload
  until some ordinary request adds a flash message and Rails raises
  `ActionDispatch::Cookies::CookieOverflow` — on the redirect, after the action already succeeded,
  which makes it read as a bug in whatever that action was. Zero now means "cache nowhere", the
  same in both branches.

  Apps on a positive TTL are unaffected.

## [0.6.0] - 2026-09-01

### Added

- **`Clowk.with_credentials`** — the settings that name an *instance* (`publishable_key`, `secret_key`, `subdomain_url`, `jwks_url`, plus the `audience` derived from the key) can now be scoped to a block instead of the process. Until now the only way to serve an app whose credentials are not a boot constant — an operator pasting a publishable key into a settings screen, or one process serving several tenants — was to call `Clowk.configure` from inside a request, mutating process-wide state from request scope with Puma threads in attendance.

  ```ruby
  around_action :require_tenant_key!

  def require_tenant_key!(&)
    Clowk.with_credentials(publishable_key: Tenant.current.key, &)
  end
  ```

  One method is the whole surface. Attributes go straight in, so the common case never names a class; a prebuilt `Clowk::Credentials` object is accepted for callers that already have one; and `nil` runs the block against the boot configuration, so "this request has no tenant" needs no branch. It is not controller-specific — the same call works in a job or a rake task — and nothing installs a callback: the `around_action` is named and placed by the app, because it has to wrap `authenticate_clowk_user!` and only the app knows what else belongs inside. A block and not a setter, because credentials that are set and never unset are precisely the hazard this exists to avoid: `secret_key` mints HS256 tokens for any subject on the path that does not check `aud`, so a scope outliving its request would be an authentication bypass rather than untidy configuration.
- `Clowk::Credentials` — the value object behind it, carrying those settings together. Separate setters would make a half-swapped state reachable between two assignments, and a publishable key from one instance beside a secret key from another is not a partial configuration, it is a broken one.
- `Clowk.credentials` — the reader everything internal now goes through. The scoped value when one is in force, `Clowk.configure`'s otherwise.

### Changed

- **`required_ruby_version` is now `>= 3.1`**, down from `>= 3.3`. 3.1 is the real floor of the code — `Clowk::SDK::Client#method_missing` declares an anonymous block parameter, which arrived in 3.1 — and the gemspec was simply stricter than it needed to be. `Clowk::Credentials` is a frozen `Struct` rather than a `Data` for the same reason: `Data` is 3.2. The freeze is what keeps the value object immutable by hand, which matters because credentials are installed into a scope and read from four places while a request runs. CI now runs 3.1 through 3.4 instead of 3.3 and 3.4, and `.standard.yml` targets 3.1 — without that the linter reports `keyword_init: true` as redundant, which it is on 3.2+ and is not on 3.1.

### Fixed

- **`audience` is now derived from the credentials in force, not from the global.** It defaults to the publishable key, so reading it off `Clowk.config` while the key came from a scoped tenant would have verified one tenant's token against another tenant's expectation — silently, on the happy path. `Clowk::Credentials` settles it at construction, so `to_h` and `==` agree with what callers see.
- README said `audience: nil` skips the `aud` check. It does not — `nil` means "derive from `publishable_key`", and only `false` switches the check off (`nil` skips solely when there is no publishable key either). The 0.5.0 note below has the same error and is left as written, being a record of what was said at the time.

### Notes

No behaviour changes for apps that configure once at boot: `Clowk.credentials` falls back to `Clowk.config`, and explicitly passed arguments still win over both. `Clowk.reset!` also clears a scoped override.

Known sharp edge, unchanged and now documented rather than fixed: `Clowk::SessionsController#new` answers with a cross-origin redirect (`allow_other_host: true`). A Turbo-driven form submission cannot follow that — the fetch is dropped and the page silently does nothing. Point a form at `/sign_in` with `data: { turbo: false }`, or use a plain link.

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
