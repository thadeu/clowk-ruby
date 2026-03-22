# Clowk Ruby SDK

Clowk is the Ruby gem for integrating Clowk authentication into Rails applications.

It focuses on a small client-side surface:

- redirect users to Clowk
- verify the JWT returned by Clowk
- expose Rails-friendly auth helpers
- provide a minimal HTTP client for the Clowk API

## Product domains

Clowk uses different domains for different concerns:

- `clowk.in`: public product site
- `app.clowk.in`: dashboard used to manage apps and instances
- `*.clowk.dev`: per-instance auth domain used by your end users

For a Rails app using this gem, the important part is the instance auth domain. Your app redirects users there, Clowk authenticates them, then redirects back with a signed JWT.

## Install

```ruby
# Gemfile
gem 'clowk'
```

## Quick start

```ruby
# config/initializers/clowk.rb
Clowk.configure do |config|
  config.secret_key = ENV['CLOWK_SECRET_KEY']
  config.publishable_key = ENV['CLOWK_PUBLISHABLE_KEY']
  config.instance_url = ENV['CLOWK_INSTANCE_URL']
  config.prefix_by = :clowk
end
```

```ruby
# config/routes.rb
Rails.application.routes.draw do
  mount Clowk::Engine => '/clowk'
end
```

```ruby
class ApplicationController < ActionController::Base
  include Clowk::Authenticable
end
```

```ruby
class DashboardController < ApplicationController
  before_action :authenticate_clowk!

  def index
    @subject = current_clowk
  end
end
```

## Authentication flow

1. Your app redirects the user to `*.clowk.dev`.
2. Clowk authenticates the user.
3. Clowk redirects back to your callback URL with `token` and `state`.
4. The gem validates `state`, verifies the JWT, stores the authenticated session, and redirects back to a safe internal path.

The callback flow includes:

- session-backed `state` validation
- JWT verification with your instance `secret_key`
- internal-only redirect sanitization
- session reset before persisting the authenticated user
- `httponly` cookie persistence with `SameSite=Lax`

## Configuration

```ruby
Clowk.configure do |config|
  config.secret_key = ENV['CLOWK_SECRET_KEY']
  config.publishable_key = ENV['CLOWK_PUBLISHABLE_KEY']
  config.instance_url = 'https://acme.clowk.dev'
  config.prefix_by = :clowk

  config.after_sign_in_path = '/'
  config.after_sign_out_path = '/'

  config.api_base_url = 'https://api.clowk.dev/client/v1'
  config.callback_path = '/clowk/oauth/callback'
  config.mount_path = '/clowk'

  config.http_open_timeout = 5
  config.http_read_timeout = 10
  config.http_write_timeout = 10
  config.http_retry_attempts = 2
  config.http_retry_interval = 0.05
  config.http_logger = Rails.logger
end
```

Important settings:

| Setting | Purpose |
| --- | --- |
| `secret_key` | Required. Used to verify JWT signatures. |
| `publishable_key` | Preferred for auth URL resolution. The gem resolves the latest instance URL from it before sign in/sign up. |
| `instance_url` | Fallback auth domain when you do not want publishable-key-based resolution. |
| `prefix_by` | Prefix used to generate helper names. Default: `:clowk`. |
| `mount_path` | Local mount prefix used by helper path generation. Default: `/clowk`. |
| `callback_path` | Callback route Clowk redirects back to. Default: `/clowk/oauth/callback`. |
| `http_logger` | Optional logger used by `Clowk::Http`. |

Auth URL resolution priority:

1. `publishable_key`
2. `instance_url`

When `publishable_key` is present, the gem resolves the current auth base URL first and caches it briefly in memory. This keeps dashboard subdomain changes visible without redeploying the client app. If you do not want that lookup, configure only `instance_url`.

Internally, that lookup is done through `Clowk::SDK` and the gem HTTP client, via `sdk.instances.find_by_key(...)`.

If you mount the engine under a different prefix, keep `mount_path` and `callback_path` aligned with that choice.

Example:

```ruby
Clowk.configure do |config|
  config.mount_path = '/auth'
  config.callback_path = '/auth/oauth/callback'
end

Rails.application.routes.draw do
  mount Clowk::Engine => '/auth'
end
```

## Generated helpers

With the default `prefix_by = :clowk`, the concern exposes:

- `current_clowk`
- `authenticate_clowk!`
- `clowk_signed_in?`

You can change the prefix to avoid collisions with another auth system.

```ruby
Clowk.configure do |config|
  config.prefix_by = :member
end
```

That generates:

- `current_member`
- `authenticate_member!`
- `member_signed_in?`

## Current subject

`current_clowk` returns a `Clowk::Current` object.

```ruby
current_clowk.id
current_clowk.email
current_clowk.name
current_clowk.avatar_url
current_clowk.provider
current_clowk.instance_id
current_clowk.app_id
```

You can also access raw claims:

```ruby
current_clowk[:sub]
current_clowk.to_h
```

## Route protection

```ruby
class AdminController < ApplicationController
  before_action :authenticate_clowk!
end
```

Use `authenticate_clowk!` for protected pages. Use `current_clowk` when the route can be public but should still know who is authenticated.

## View and URL helpers

Local mounted routes:

```erb
<%= link_to 'Sign in', clowk_sign_in_path(return_to: dashboard_path) %>
<%= link_to 'Sign up', clowk_sign_up_path(return_to: dashboard_path) %>
<%= link_to 'Sign out', clowk_sign_out_path %>
```

Direct remote URLs:

```erb
<%= link_to 'Direct sign in', clowk_sign_in_url(redirect_to: dashboard_url) %>
<%= link_to 'Direct sign up', clowk_sign_up_url(redirect_to: dashboard_url) %>
```

When `publishable_key` is configured, these helpers resolve the latest instance URL before building the final `sign-in` or `sign-up` destination. When it is absent, they use `instance_url` directly.

Mounted routes exposed by the engine:

- `/clowk/sign_in`
- `/clowk/sign_up`
- `/clowk/sign_out`
- `/clowk/oauth/callback`

When you mount the engine elsewhere, the same route set is exposed under your chosen prefix.

## Token sources

The concern can read the token from:

- `params[:token]`
- cookies
- `Authorization: Bearer <token>`

That keeps the integration usable for callback routes, regular controllers, and API-style endpoints.

## API client

The gem includes a small client for Clowk API requests.

```ruby
client = Clowk::Client::SDK.new

response = client.verify_token(token: params[:token])

response.status
response.success?
response.body
response.body_parsed
response.headers
```

There is also a short alias:

```ruby
client = Clowk::SDK.new
user = client.users.find('user_123')
instance = client.instances.find_by_key(key: 'pk_live_123')
```

The SDK organizes resources through `Clowk::SDK::Resourceable`:

- `users`
- `instances`
- `webhooks`
- `sessions`

Convenience shortcuts can still exist for common paths, such as `client.user('user_123')`, but the resource-oriented API is the main structure.

Supported instance methods:

- `get`
- `post`
- `put`
- `patch`
- `delete`
- `head`
- `options`
- `verify_token`
- `user`
- `users`
- `instances`
- `webhooks`
- `sessions`

## `Clowk::Http::Response`

HTTP responses are returned as `Clowk::Http::Response` objects.

```ruby
response = client.get('users/user_123')

response.status       # => 200
response.success?     # => true
response.body         # => '{"id":"user_123"}'
response.body_parsed  # => { 'id' => 'user_123' }
response.headers      # => { 'content-type' => ['application/json'] }
```

For compatibility, the response also supports:

```ruby
response[:status]
response[:success?]
response.to_h
```

## HTTP middleware

`Clowk::Http` uses a small internal middleware stack built on `Net::HTTP`.

Included behavior:

- request and response logging
- open, read, and write timeouts
- retry on retryable network errors
- automatic JSON request encoding
- automatic `body_parsed` JSON decoding when possible

## Scope

This gem is intentionally narrow. It does not try to replace your entire app session architecture or act as an auth server.

Its job is to make the Rails side of Clowk integration predictable:

- start authentication
- validate callbacks safely
- expose a clean authenticated subject
- make future Clowk API access straightforward

## License

MIT. See `LICENSE`.
