# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
