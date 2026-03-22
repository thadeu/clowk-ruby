# Clowk — Claude Code Instructions

## Project

Clowk is a self-hosted authentication broker for Ruby on Rails apps. It acts as an OAuth proxy: client apps redirect to Clowk, which handles the OAuth dance with Google/GitHub/Twitter and returns a signed JWT.

Live at: https://clowk.in
Dashboard at: https://clowk.in/dashboard

## Stack

- Ruby 3.4 / Rails 8.1 (full-stack, not API-only)
- PostgreSQL with UUID primary keys
- Tailwind CSS
- Hotwire / Turbo (no React, no Vue)
- Faraday for HTTP
- JWT gem (HS256)
- Active Record Encryption (secret keys)
- No Devise, OmniAuth, or Doorkeeper — intentional

## Lint, Style, Layout

- Avoid write code without breakline
- Create code context-based separating using breakline
- DONT CREATE COMMENT in our code, just only if needed to documentation method or class usando RDOC ou YARD

## Changes

- Always update CHANGELOG.md when version will change

## Data model

```
Organization (tenant)
  └── Membership (account_id, role)
  └── Workspace
        └── App (name, display_name, logo_url)
              └── Instance (environment: dev|prod)
                    ├── publishable_key (pk_...)
                    ├── secret_key (sk_..., encrypted)
                    ├── secret_key_prefix (first 16 chars, for fast lookup)
                    ├── enabled_providers []
                    ├── allowed_redirect_uris []
                    ├── internal (bool — Clowk's own dashboard instance)
                    └── User
                          └── Identity (polymorphic, provider + uid + tokens)

Account (dashboard user / developer)
  └── Membership → Organization
  └── Identity (polymorphic)

OAuthState (anti-CSRF, TTL 10min, stores code_verifier for Twitter PKCE)
```

## Key conventions

- Secret key lookup: prefix-based (`secret_key_prefix`) → AR Encryption decrypt → compare
- JWT `iss: "clowk"`, signed with `instance.secret_key`
- Twitter requires PKCE — `code_verifier` stored in `OAuthState`
- Twitter has no email — placeholder: `twitter_UID@clowk.noemail`
- OAuth links need `data: { turbo: false }` to bypass Turbo Drive
- `ERB::Util.url_encode` in views (not `CGI.escape`)
- `button_to` must never be nested inside `link_to` (invalid HTML)
- Base URL for OAuth callbacks: `Rails.application.config.clowk_base_url` (read dynamically, not a constant)

## Dashboard auth flow

The dashboard uses Clowk itself for login:
1. `Instance.find_by(internal: true)` → the Clowk internal instance
2. Unauthenticated request → redirect to `/login?client_id=pk_xxx&redirect_uri=/dashboard/auth/callback`
3. `Dashboard::AuthController#callback` → decode JWT → find/create Account → find/create Organization → store in session
4. All dashboard controllers inherit from `Dashboard::BaseController` which enforces `current_account`

## Important files

- `app/services/oauth/` — one file per provider (google, github, twitter)
- `app/services/oauth/provider_factory.rb` — reads credentials from Rails.credentials or ENV
- `app/services/jwt_service.rb` — encode/decode, `token_for_user`
- `app/services/user_normalizer.rb` — find_or_create User + Identity
- `app/controllers/oauth/authorizations_controller.rb` — validates client_id, generates OAuthState
- `app/controllers/oauth/callbacks_controller.rb` — handles provider callback, issues JWT
- `app/controllers/dashboard/application_controller.rb` — base for all dashboard controllers
- `db/seeds.rb` — creates only the internal Clowk organization

## Environment variables

```
CLOWK_BASE_URL=http://localhost:3000
GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET
GITHUB_CLIENT_ID / GITHUB_CLIENT_SECRET
TWITTER_CLIENT_ID / TWITTER_CLIENT_SECRET
```

## Testing

- **Always create tests** for new features, controllers, models, and services
- **Always run `bundle exec rspec`** after every change to ensure nothing is broken
- Tests live in `spec/` following standard RSpec + FactoryBot conventions
- Request specs in `spec/controllers/` (type: :request)
- Model specs in `spec/models/`

## Common tasks

**Run tests:**
```bash
bundle exec rspec
```

**Reset and reseed:**
```bash
bin/rails runner "User.destroy_all; OAuthState.destroy_all; Identity.destroy_all; Instance.destroy_all; App.destroy_all; Workspace.destroy_all; Membership.destroy_all; Organization.destroy_all; Account.destroy_all"
bin/rails db:seed
```

**Run:**
```bash
bin/dev
```

## What NOT to do

- Do not add Devise, OmniAuth, or Doorkeeper
- Do not store plain-text secret keys — always use AR Encryption
- Do not use `CGI.escape` in views
- Do not nest `button_to` inside `link_to`
- Do not use `CLOWK_BASE_URL` as a Ruby constant — always read from `config` at runtime
- Do not add JavaScript frameworks
