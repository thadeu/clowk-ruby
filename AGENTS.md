# Clowk — AI Agent Instructions

## Project overview

Clowk is a self-hosted OAuth authentication broker for Ruby on Rails apps. Client apps redirect users to Clowk for login; Clowk handles OAuth with Google/GitHub/Twitter and returns a signed JWT.

- Language: Ruby 3.4
- Framework: Rails 8.1 (full-stack)
- Database: PostgreSQL (UUID primary keys)
- Frontend: Tailwind CSS + Hotwire/Turbo
- No Devise, OmniAuth, or Doorkeeper

## Data hierarchy

```
Organization → Workspace → App → Instance → User → Identity
Account → Membership → Organization
OAuthState (ephemeral, anti-CSRF)
```

Instances hold all functional config: `publishable_key`, `secret_key` (encrypted), `enabled_providers`, `allowed_redirect_uris`. Apps are organizational containers only.

## Before making changes

1. Read the relevant file before editing it
2. Check existing patterns — controllers are thin, logic lives in `app/services/`
3. Never nest `button_to` inside `link_to`
4. Never use `CGI.escape` in views — use `ERB::Util.url_encode`
5. Never store plain-text secret keys

## Running the app

```bash
bin/dev                        # start server
bin/rails db:migrate           # run migrations
bin/rails db:seed              # seed internal org only
```

## Testing

- **Always create tests** for new features, controllers, models, and services — no code change should go untested
- **Always run `bundle exec rspec`** after every change to ensure nothing is broken
- Tests use RSpec + FactoryBot. Request specs in `spec/controllers/`, model specs in `spec/models/`
- Factories live in `spec/factories/`

```bash
bundle exec rspec              # run all tests
bundle exec rspec spec/models/ # run model specs only
```

Manual verification (in addition to tests):
- OAuth flow: visit `/login?client_id=pk_xxx&redirect_uri=http://localhost:3001/auth/callback`
- Dashboard: visit `/` — should redirect to login if unauthenticated
- API: `POST /api/v1/tokens/verify` with `X-Clowk-Secret-Key` header

## Key service objects

| File | Purpose |
|------|---------|
| `app/services/oauth/google.rb` | Google OAuth 2.0 + OIDC |
| `app/services/oauth/github.rb` | GitHub OAuth 2.0 |
| `app/services/oauth/twitter.rb` | Twitter OAuth 2.0 + PKCE |
| `app/services/oauth/provider_factory.rb` | Loads provider credentials |
| `app/services/jwt_service.rb` | Encode/decode JWT (HS256) |
| `app/services/user_normalizer.rb` | Find or create User + Identity |

## OAuth callback URL

Always read dynamically — never cache as a constant:
```ruby
Rails.application.config.clowk_base_url  # not a constant
```

## Secret key lookup pattern

```ruby
# Fast: find by prefix, then decrypt and compare
Instance.find_by_secret_key(key)
# prefix = key[0, 16] → find_by(secret_key_prefix:) → instance.secret_key == key
```

## Adding a migration

```bash
bin/rails generate migration DescriptiveName
# edit the generated file
bin/rails db:migrate
```

Always use `id: :uuid` for new tables and `type: :uuid` on foreign key references.

## Dashboard authentication

The dashboard authenticates via Clowk itself. The internal instance (`Instance.find_by(internal: true)`) is seeded at setup. Session stores `account_id` and `organization_id`. All dashboard controllers inherit from `Dashboard::BaseController`.

## Hard rules

- No plain-text secret keys anywhere
- No Devise / OmniAuth / Doorkeeper
- No React / Vue / other JS frameworks
- OAuth links must have `data: { turbo: false }`
- `button_to` and `link_to` must never be nested
- Use `ERB::Util.url_encode` not `CGI.escape` in views
