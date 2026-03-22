# Clowk SDK — Architecture Specification

This document defines the standard architecture for building Clowk SDKs in any language.
Use it as the reference when creating new SDKs (Node.js, JavaScript, React, Go, Python, etc.).

The Ruby SDK (`clowk-ruby`) is the reference implementation.

## Product context

Clowk is a self-hosted authentication broker. Client apps redirect users to Clowk, which handles OAuth (Google, GitHub, Twitter) and returns a signed JWT.

- `clowk.in` — product site
- `app.clowk.in` — dashboard
- `*.clowk.dev` — per-instance auth domain (used by end users)
- `api.clowk.dev/client/v1` — API base URL

## SDK layers

Every Clowk SDK must implement these layers:

```
┌─────────────────────────────────────────────┐
│  Framework Integration (Rails, Next.js, etc)│
│  - Auth middleware / hooks                  │
│  - URL helpers (sign_in, sign_up, sign_out) │
│  - Token extraction (params, cookie, header)│
├─────────────────────────────────────────────┤
│  JWT Verifier                               │
│  - HS256 verification                       │
│  - Issuer validation                        │
│  - Expiration check                         │
├─────────────────────────────────────────────┤
│  SDK Client (resource-oriented API)         │
│  - client.users                             │
│  - client.sessions                          │
│  - client.subdomains                        │
│  - client.tokens                            │
├─────────────────────────────────────────────┤
│  Resource (base CRUD)                       │
│  - list, find, show, search, destroy        │
├─────────────────────────────────────────────┤
│  HTTP Client                                │
│  - Built on native HTTP (no external deps)  │
│  - Middleware stack                          │
│  - Retry, timeout, logger                   │
│  - Response body size limit (1 MB)          │
├─────────────────────────────────────────────┤
│  Configuration                              │
│  - Singleton config with sensible defaults  │
│  - Yielded block / builder pattern          │
├─────────────────────────────────────────────┤
│  Errors                                     │
│  - ClowkError (base)                        │
│  - ConfigurationError                       │
│  - InvalidStateError                        │
│  - InvalidTokenError                        │
└─────────────────────────────────────────────┘
```

---

## 1. Configuration

Singleton configuration with sensible defaults. Must support a builder/callback pattern.

### Required settings

| Setting | Default | Description |
|---|---|---|
| `apiBaseUrl` | `https://api.clowk.dev/client/v1` | API endpoint |
| `appBaseUrl` | `https://app.clowk.in` | Dashboard URL |
| `secretKey` | `null` | Instance secret key (for JWT verification) |
| `publishableKey` | `null` | Instance publishable key (for subdomain resolution) |
| `subdomainUrl` | `null` | Fallback auth domain URL |
| `afterSignInPath` | `/` | Redirect after sign in |
| `afterSignOutPath` | `/` | Redirect after sign out |
| `mountPath` | `/clowk` | Local mount prefix |
| `callbackPath` | `/clowk/oauth/callback` | OAuth callback route |
| `cookieKey` | `clowk_token` | Cookie name for token |
| `sessionKey` | `clowk` | Session key |
| `tokenParam` | `token` | Query param name for token |
| `issuer` | `clowk` | Expected JWT issuer |

### HTTP settings

| Setting | Default | Description |
|---|---|---|
| `httpOpenTimeout` | `5` (seconds) | Connection timeout |
| `httpReadTimeout` | `10` (seconds) | Read timeout |
| `httpWriteTimeout` | `10` (seconds) | Write timeout |
| `httpRetryAttempts` | `2` | Retries on network errors |
| `httpRetryInterval` | `0.05` (seconds) | Delay between retries |
| `httpLogger` | `null` | Optional logger instance |

### Usage pattern

```javascript
// JavaScript
Clowk.configure({
  secretKey: process.env.CLOWK_SECRET_KEY,
  publishableKey: process.env.CLOWK_PUBLISHABLE_KEY,
})

// or builder
const clowk = new Clowk({
  secretKey: '...',
  publishableKey: '...',
})
```

```ruby
# Ruby (reference)
Clowk.configure do |config|
  config.secret_key = ENV['CLOWK_SECRET_KEY']
  config.publishable_key = ENV['CLOWK_PUBLISHABLE_KEY']
end
```

---

## 2. Error hierarchy

Every SDK must define typed errors for precise error handling.

```
ClowkError (base)
├── ConfigurationError  — missing keys, invalid config
├── InvalidStateError   — CSRF state mismatch
└── InvalidTokenError   — JWT decode/verify/expired/issuer errors
```

---

## 3. HTTP Client

Built on the language's native HTTP library. No external HTTP dependencies.

### Middleware stack

The HTTP client uses a composable middleware stack (inspired by Rack/Express):

```
Request → TimeoutMiddleware → RetryMiddleware → LoggerMiddleware → HTTP execution
```

Each middleware wraps the next, receives an `env` object, and returns a response.

### Middleware: Timeout

Sets connection, read, and write timeouts on the HTTP request.

### Middleware: Retry

Retries on transient network errors only:

- Connection reset
- Connection timeout
- Read timeout
- Write timeout
- Socket errors
- EOF errors

Does NOT retry on HTTP status errors (4xx, 5xx). Those are returned as-is.

### Middleware: Logger

Logs request method + URL before, and status code after.

```
[Clowk::Http] GET https://api.clowk.dev/client/v1/users/user_123
[Clowk::Http] -> 200
```

### Response object

Every HTTP response must be wrapped in a standard response object:

```
Response {
  status: number        // HTTP status code
  body: string          // Raw response body
  bodyParsed: object    // JSON-parsed body (null if not JSON)
  headers: object       // Response headers
  success: boolean      // true if 2xx
}
```

### Safety

- Max response body size: **1 MB** (1_048_576 bytes). Raise `ClowkError` if exceeded.
- Default headers: `Accept: application/json`, `Content-Type: application/json`
- Auth headers sent when keys are present:
  - `X-Clowk-Secret-Key: sk_...`
  - `X-Clowk-Publishable-Key: pk_...`

### HTTP methods

The client must support: `GET`, `POST`, `PUT`, `PATCH`, `DELETE`, `HEAD`, `OPTIONS`.

---

## 4. SDK Client

The main entry point. Creates resource accessors dynamically.

### Public API

```javascript
const client = new Clowk.Client({
  apiBaseUrl: '...',     // optional, uses config default
  secretKey: '...',      // optional, uses config default
  publishableKey: '...', // optional, uses config default
})

client.users        // → UserResource
client.sessions     // → SessionResource
client.subdomains   // → SubdomainResource
client.tokens       // → TokenResource
```

### How it works

1. Client receives a method call (e.g., `.users`)
2. Singularizes the name (`users` → `User`)
3. Looks up the resource class (`User`)
4. Instantiates it with `self` (the client) as dependency
5. Memoizes the instance for reuse

### HTTP delegation

The client delegates raw HTTP methods to the internal HTTP client:

```javascript
client.get('custom/endpoint')
client.post('custom/endpoint', { key: 'value' })
client.put('custom/endpoint', { key: 'value' })
client.patch('custom/endpoint', { key: 'value' })
client.delete('custom/endpoint')
client.head('custom/endpoint')
client.options('custom/endpoint')
```

---

## 5. Resource (base class)

Every resource extends a base class with standard CRUD operations.

### Base methods

| Method | HTTP | Path |
|---|---|---|
| `list()` | GET | `/{resource_path}` |
| `find(id)` | GET | `/{resource_path}/{id}` |
| `show(id)` | GET | `/{resource_path}/{id}` |
| `search(filters)` | GET | `/{resource_path}/search?query=...` |
| `destroy(id)` | DELETE | `/{resource_path}/{id}` |

### Search operators (Zendesk-style)

The `search` method supports two modes:

**Keywords** (object/hash):

```javascript
client.users.search({ email: 'user@example.com', status: 'active' })
// GET /users/search?query=email%3Auser%40example.com+status%3Aactive
```

Joins key-value pairs as `key:value`, separated by spaces.

**Raw string** (for advanced operators like `>`, `<`, `>=`):

```javascript
client.users.search('email:user@example.com active:true created_at>2026-01-01')
// GET /users/search?query=email%3Auser%40example.com+active%3Atrue+created_at%3E2026-01-01
```

The raw string is URL-encoded and sent as-is.

### Resource registry

| Resource | Path | Custom methods |
|---|---|---|
| `User` | `users` | — |
| `Session` | `sessions` | — |
| `Subdomain` | `instances` | `findByPk(key)` |
| `Token` | `tokens` | `verify({ token })` |

### Subdomain resource

```javascript
// findByPk delegates to search internally
client.subdomains.findByPk('pk_live_xxx')
// → search({ publishable_key: 'pk_live_xxx' })
// → GET /instances/search?query=publishable_key%3Apk_live_xxx
```

### Token resource

```javascript
client.tokens.verify({ token: 'jwt_token' })
// → POST /tokens/verify { token: 'jwt_token' }
```

---

## 6. JWT Verifier

### Spec

- Algorithm: **HS256**
- Key: instance `secretKey`
- Issuer: `clowk` (configurable, optional)
- Raises `ConfigurationError` if `secretKey` is missing/empty
- Raises `InvalidTokenError` for: decode errors, verification errors, expired tokens, invalid issuer
- Returns decoded payload as object with symbolized/camelCase keys

### Error mapping

| JWT error | Clowk error |
|---|---|
| Missing secret key | `ConfigurationError` |
| Decode failure | `InvalidTokenError` |
| Signature mismatch | `InvalidTokenError` |
| Token expired | `InvalidTokenError` |
| Issuer mismatch | `InvalidTokenError` |

---

## 7. Subdomain Resolver

Resolves the auth base URL for the current instance. Used by URL helpers.

### Resolution priority

1. `publishableKey` → API lookup → cache
2. `subdomainUrl` → direct (normalized)
3. Neither → raise `ConfigurationError`

### Caching

- Cache TTL: **60 seconds**
- Cache key: `instance-url:{publishableKey}`
- In-memory cache (no external deps)
- `clearCache()` method for testing

### URL extraction from API response

The API may return different payload shapes. Extract the URL in this order:

1. `payload.instance.url` or `payload.instance.subdomain_url` or `payload.instance.instance_url`
2. `payload.instance.host` or `payload.instance.domain` or `payload.instance.hostname` → prepend `https://`
3. `payload.instance.subdomain` → build `https://{subdomain}.clowk.dev`
4. Same fields at root level (without `instance` wrapper)

Always normalize: strip trailing slashes.

---

## 8. Token Extractor

Extracts the JWT token from incoming requests. Checks sources in order:

1. **Query params**: `request.params[tokenParam]`
2. **Authorization header**: `Bearer {token}`
3. **Cookies**: `request.cookies[cookieKey]`

First non-empty value wins.

---

## 9. URL Helpers

Generate sign-in, sign-up, and sign-out URLs.

### Local paths (mount-based)

```
clowkSignInPath(returnTo?)   → {mountPath}/sign_in?return_to=...
clowkSignUpPath(returnTo?)   → {mountPath}/sign_up?return_to=...
clowkSignOutPath(returnTo?)  → {mountPath}/sign_out?return_to=...
```

### Remote URLs (direct to Clowk instance)

```
clowkSignInUrl(redirectTo?)  → https://{subdomain}.clowk.dev/sign-in?redirect_uri=...
clowkSignUpUrl(redirectTo?)  → https://{subdomain}.clowk.dev/sign-up?redirect_uri=...
```

Remote URLs resolve the subdomain first (via SubdomainResolver) and include the callback URL.

---

## 10. Auth middleware / hooks

Framework-specific layer that ties everything together.

### Responsibilities

- `currentUser` / `currentClowk` — returns decoded JWT payload or null
- `authenticate!` — redirects to sign-in (web) or returns 401 (API)
- `signedIn?` — boolean check
- `signOut!` — clears session + cookie
- Session persistence: store token + decoded payload + timestamp
- Cookie: `httpOnly`, `sameSite: lax`, `secure` when HTTPS

### Token flow

1. Check session for stored payload → return if valid
2. Extract token from request (TokenExtractor)
3. Verify with JwtVerifier
4. Persist to session + cookie
5. Return `Current` object

---

## 11. Framework packages

The SDK should be split into packages per framework:

| Package | Contains | Depends on |
|---|---|---|
| `@clowk/core` | Config, Errors, HTTP Client, SDK Client, Resources, JWT Verifier, Subdomain Resolver | nothing |
| `@clowk/node` | Token Extractor for Node.js, Express/Fastify middleware | `@clowk/core` |
| `@clowk/react` | React hooks (`useClowk`, `useAuth`), `ClowkProvider`, `SignInButton`, `SignUpButton` | `@clowk/core` |
| `@clowk/nextjs` | Next.js middleware, server actions, route handlers | `@clowk/core`, `@clowk/react` |

### `@clowk/core` — file structure

```
src/
├── index.ts               # Public exports
├── config.ts              # Configuration singleton
├── errors.ts              # ClowkError, ConfigurationError, InvalidStateError, InvalidTokenError
├── http/
│   ├── client.ts          # HTTP client with middleware stack
│   ├── response.ts        # Response wrapper
│   └── middleware/
│       ├── timeout.ts
│       ├── retry.ts
│       └── logger.ts
├── sdk/
│   ├── client.ts          # SDK Client (resource accessor)
│   ├── resource.ts        # Base Resource (list, find, show, search, destroy)
│   ├── user.ts            # User resource
│   ├── session.ts         # Session resource
│   ├── subdomain.ts       # Subdomain resource (findByPk)
│   └── token.ts           # Token resource (verify)
├── jwt-verifier.ts        # JWT decode + verify
├── subdomain-resolver.ts  # Subdomain URL resolution + cache
└── types.ts               # Shared TypeScript types
```

### `@clowk/react` — file structure

```
src/
├── index.ts
├── provider.tsx            # ClowkProvider (React context)
├── hooks/
│   ├── use-clowk.ts       # useClowk() — returns client instance
│   ├── use-auth.ts         # useAuth() — returns { user, signedIn, signIn, signOut }
│   └── use-token.ts        # useToken() — returns current token
└── components/
    ├── sign-in-button.tsx
    ├── sign-up-button.tsx
    └── sign-out-button.tsx
```

---

## 12. Testing requirements

Every SDK must have tests for:

### HTTP layer
- All HTTP methods (GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS)
- JSON encoding/decoding
- Non-JSON responses (raw body, `bodyParsed` is null)
- Timeout middleware applies correct timeouts
- Retry middleware retries on transient errors
- Retry middleware raises after exhausting attempts
- Logger middleware logs request/response
- Response body size limit (> 1 MB raises error)
- HTTP 5xx responses (500, 502, 503)

### SDK Client
- Resource accessors return correct types
- Resource memoization (same instance on repeated calls)
- HTTP delegation (get, post, put, patch, delete, head, options)

### Resources
- `list`, `find`, `show`, `destroy` hit correct paths
- `search` with keywords builds `field:value` query
- `search` with raw string passes through
- Token `verify` sends POST
- Subdomain `findByPk` delegates to `search`

### JWT Verifier
- Valid token decodes correctly
- Missing secret key raises `ConfigurationError`
- Expired token raises `InvalidTokenError`
- Wrong key raises `InvalidTokenError`
- Malformed token raises `InvalidTokenError`
- Invalid issuer raises `InvalidTokenError`
- Null issuer skips issuer verification

### Subdomain Resolver
- Resolves from `publishableKey` via API
- Falls back to `subdomainUrl`
- Raises `ConfigurationError` when both are missing
- Caches resolved URL
- Extracts URL from nested payload shapes

---

## 13. Naming conventions

| Concept | Ruby | JavaScript/TypeScript |
|---|---|---|
| Package | `clowk` (gem) | `@clowk/core`, `@clowk/react`, etc |
| Config | `Clowk.configure { \|c\| ... }` | `Clowk.configure({ ... })` |
| Client | `Clowk::SDK::Client.new` | `new Clowk.Client()` or `new ClowkClient()` |
| Resource | `Clowk::SDK::Resource` | `ClowkResource` |
| Error | `Clowk::Error` | `ClowkError` |
| Method names | `snake_case` | `camelCase` |
| Config keys | `snake_case` | `camelCase` |
| API headers | `X-Clowk-Secret-Key` | `X-Clowk-Secret-Key` (same) |
| Resource path | `self.resource_path` (class method) | `static resourcePath` |

---

## 14. Non-negotiable rules

1. No external HTTP dependencies — use native HTTP only
2. No external auth libraries (Passport, Devise, etc)
3. JWT always HS256, issuer always `clowk`
4. Secret keys never logged, never in plain text responses
5. API headers: `X-Clowk-Secret-Key`, `X-Clowk-Publishable-Key`
6. Max response body: 1 MB
7. Retry only transient network errors, never HTTP status errors
8. Search uses Zendesk-style `field:value` operators
9. Subdomain resolution cached for 60 seconds
10. Token extraction order: params → bearer → cookie
11. Cookie: `httpOnly`, `sameSite: lax`, `secure` on HTTPS
12. Always test: timeouts, 5xx, expired JWT, body size limit
