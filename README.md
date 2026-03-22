# Clowk Rails

Ruby gem for integrating Clowk authentication into Rails applications.

The goal is the same developer experience that made Clerk popular, but with a Rails-native integration: simple setup, server-side JWT verification, and helpers that feel natural inside a Rails app.

## What this gem does

- Verify HS256 JWTs issued by Clowk
- Validate token expiration and signature with your instance `secret_key`
- Expose Rails helpers such as `current_clowk` and `authenticate_clowk!`
- Extract the token from query params, cookies, or the `Authorization` header
- Build sign-in and sign-up URLs for your Clowk instance

## Clowk domains

Clowk uses different domains for different parts of the product:

- `clowk.in`: marketing and public site
- `app.clowk.in`: dashboard where your customer creates apps, instances, and configures auth
- `*.clowk.dev`: unique auth domain for each customer instance, where end users actually sign in

For the Rails app using this gem, the important part is simple: your users authenticate on your instance domain on `clowk.dev`, and your app receives a signed JWT back.

## Auth flow

1. Your Rails app redirects the user to your instance sign-in URL on `*.clowk.dev`
2. The user authenticates on Clowk with OAuth or email/password
3. Clowk redirects back to your `redirect_uri` with `?token=eyJ...`
4. This gem verifies the JWT using your instance `secret_key`
5. The authenticated user payload becomes available in Rails through `current_clowk`

## Quick start

```ruby
# config/initializers/clowk.rb
Clowk.configure do |config|
  config.secret_key = ENV["CLOWK_SECRET_KEY"]
  config.publishable_key = ENV["CLOWK_PUBLISHABLE_KEY"]
  config.instance_url = ENV["CLOWK_INSTANCE_URL"]
  config.prefix_by = :clowk
end
```

| Key | Description |
|-----|-------------|
| `secret_key` | Instance secret key (`sk_...`). Required. Used to verify JWT signatures. |
| `publishable_key` | Instance publishable key (`pk_...`). Optional. Used to build auth URLs through `app.clowk.in`. |
| `instance_url` | Optional explicit auth domain, such as `https://acme.clowk.dev`. |
| `prefix_by` | Prefix used to generate auth helper methods. Default is `:clowk`. |

```ruby
# config/routes.rb
Rails.application.routes.draw do
  mount Clowk::Engine => "/clowk"
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
    @user = current_clowk
  end
end
```

## Custom helper names

If you want to avoid collisions with Devise or other auth libraries, you can change the helper prefix:

```ruby
Clowk.configure do |config|
  config.prefix_by = :member
end
```

That gives you:

- `current_member`
- `authenticate_member!`
- `member_signed_in?`

## What `current_clowk` contains

After a valid token is processed, the user payload is available in your controllers.

```ruby
current_clowk
# => {
#   id: "uuid",
#   email: "user@example.com",
#   name: "John Doe",
#   avatar_url: "https://...",
#   provider: "google"
# }
```

Depending on the token payload, Clowk may also include internal identifiers such as the instance and app ids.

## Route protection

```ruby
class AdminController < ApplicationController
  include Clowk::Authenticable

  before_action :authenticate_clowk!
end
```

Use `authenticate_clowk!` when the route requires a valid authenticated user. Use `current_clowk` when the route can be public but should still know who is signed in.

When the user is not authenticated, the concern redirects to the local engine route on `/clowk/sign_in`, which then redirects to your Clowk instance and uses `/clowk/oauth/callback` to receive the JWT back.

## View helpers

```erb
<%= link_to "Sign in", clowk_sign_in_path(return_to: dashboard_path) %>
<%= link_to "Sign up", clowk_sign_up_path(return_to: dashboard_path) %>
```

If you want the direct remote URLs instead of the local mounted routes:

```erb
<%= link_to "Direct sign in", clowk_sign_in_url(redirect_to: dashboard_url) %>
<%= link_to "Direct sign up", clowk_sign_up_url(redirect_to: dashboard_url) %>
```

The helpers are meant to keep the integration small on the client side: configure your keys, mount the engine, redirect to Clowk, verify the token, and use `current_clowk`.

## Callback flow

Once the engine is mounted, the gem exposes these routes:

- `/clowk/sign_in`
- `/clowk/sign_up`
- `/clowk/sign_out`
- `/clowk/oauth/callback`

The callback validates the JWT, stores it in the Rails session, persists the raw token in a cookie, and redirects back to the original `return_to` path.

## API client

The gem also ships with a small SDK client for the future Clowk API.

```ruby
sdk = Clowk::Client::SDK.new

result = sdk.verify_token(token: params[:token])
result[:success?] # => true
result[:body]     # => parsed JSON response
```

There is also a convenience alias if you prefer a shorter name:

```ruby
sdk = Clowk::SDK.new
user = sdk.user("user_123")
```

## Request sources

The gem can read the token from:

- `params[:token]`
- cookies
- `Authorization: Bearer <token>`

This makes it work for classic Rails controllers, callback flows, and API endpoints without extra glue code.

## Intended scope

This gem is intentionally narrow. It is not an auth server and it does not try to own your full session architecture.

It focuses on the client side of the integration:

- receive the token from Clowk
- verify it safely
- expose a clean Rails API

## Gem structure

```
clowk-rails/
├── config/
│   └── routes.rb
├── lib/
│   └── clowk/
│       ├── configuration.rb
│       ├── current.rb
│       ├── client.rb
│       ├── jwt_verifier.rb
│       ├── authenticable.rb
│       ├── engine.rb
│       ├── controllers/
│       ├── helpers/
│       └── middleware/
├── lib/clowk.rb
├── clowk.gemspec
└── README.md
```

## Companion SDKs

Clowk can also be consumed from JavaScript and TypeScript apps through the `clowk-js` SDKs, while this gem focuses on the Rails experience.

---

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](./CONTRIBUTING.md) for guidelines.

---

## License

[GNU Affero General Public License v3.0](./LICENSE) — AGPL-3.0

If you run a modified version of Clowk as a network service, you must make your source code available to users of that service.
