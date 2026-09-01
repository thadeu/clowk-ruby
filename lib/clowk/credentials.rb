# frozen_string_literal: true

require "active_support/isolated_execution_state"

module Clowk
  # Credentials — which Clowk instance is answering, right here, right now.
  #
  # Everything else in Configuration describes the HOST: where the callback
  # lives, how long HTTP waits, what the helpers are called. Those are decided
  # once, at boot, by the person who wrote the initializer. These four are
  # different — they name an instance, and an app that lets an operator paste a
  # publishable key into a settings screen, or that serves several tenants from
  # one process, has to be able to answer "which instance" per request rather
  # than per process.
  #
  # A value object rather than four accessors because they only mean anything
  # together. A publishable key from one instance beside a secret key from
  # another is not a partial configuration, it is a broken one, and separate
  # setters make that state reachable in between two assignments.
  #
  # `audience` defaults to the publishable key, which is what Clowk stamps into
  # `aud` — the same rule Configuration#audience has always had, and it is
  # carried here rather than left on the global for the reason this class
  # exists: a SCOPED publishable key must be checked against a scoped audience.
  # Reading the audience off the global while the key came from a tenant would
  # verify one tenant's token against another tenant's expectation, silently,
  # on the happy path. Pass `false` to switch the check off.
  #
  # See Clowk.with_credentials for why the scoped form is a block and not a
  # setter.
  # A Struct rather than a Data, and frozen by hand, so the gem keeps running on
  # Ruby 3.1 — `Data` arrived in 3.2. The freeze is not decoration: credentials
  # are installed into a scope and read from four places while a request runs,
  # and a member somebody could reassign halfway through would be the
  # half-swapped state this class exists to make unreachable.
  Credentials = Struct.new(:publishable_key, :secret_key, :subdomain_url, :jwks_url, :audience,
    keyword_init: true) do
    # Every member optional: an app that only sets a publishable key is the
    # common case, and RS256 needs nothing else.
    #
    # `audience` is DERIVED HERE, at construction, rather than in the reader.
    # Deriving it on read would mean `to_h` and `==` saw nil while callers saw
    # the publishable key — a value object that disagrees with itself. Settled
    # once, so what it holds is what it means.
    def initialize(publishable_key: nil, secret_key: nil, subdomain_url: nil,
      jwks_url: nil, audience: nil)
      super(
        publishable_key: publishable_key,
        secret_key: secret_key,
        subdomain_url: subdomain_url,
        jwks_url: jwks_url,
        audience: audience.nil? ? publishable_key : audience
      )

      freeze
    end

    # The boot configuration, as credentials. This is what `Clowk.credentials`
    # falls back to, so an installation that configures once and never scopes
    # anything behaves exactly as it did before this existed.
    def self.from(config)
      new(
        publishable_key: config.publishable_key,
        secret_key: config.secret_key,
        subdomain_url: config.subdomain_url,
        jwks_url: config.jwks_url,
        audience: config.audience
      )
    end
  end

  class << self
    # The credentials in force for the current execution context.
    #
    # The scoped override if there is one, the boot configuration otherwise.
    # Read this instead of Clowk.config wherever an instance is being named, so
    # a consumer that never scopes anything pays nothing and a consumer that
    # does is served correctly.
    def credentials
      ActiveSupport::IsolatedExecutionState[:clowk_credentials] || Credentials.from(config)
    end

    # Run a block against a particular Clowk instance.
    #
    # THE ONLY METHOD AN APP EVER CALLS. Attributes go straight in, so the
    # common case never has to name the Credentials class:
    #
    #   Clowk.with_credentials(publishable_key: tenant.key) do
    #     # sign-in URLs, JWKS, verification and the API client
    #     # all resolve against that instance in here
    #   end
    #
    # A prebuilt object works too, for callers that already have one — an
    # ActiveRecord row that knows how to describe itself, say:
    #
    #   Clowk.with_credentials(tenant.clowk_credentials) { … }
    #
    # And nil runs the block against the boot configuration, so "this request
    # has no tenant" needs no branch at the call site:
    #
    #   Clowk.with_credentials(tenant&.clowk_credentials) { … }
    #
    # A BLOCK, AND DELIBERATELY NOT A SETTER. `Clowk.secret_key = x` has no
    # lifetime: the first request that raises between the assignment and its
    # reset leaves that key installed process-wide, and the secret key mints
    # HS256 tokens for any subject — Clowk::JwtVerifier routes to the symmetric
    # path whenever `alg` is not RS256, and that path does not check the
    # audience. So a leaked scope is not an untidy configuration, it is an
    # authentication bypass. The `ensure` below is the whole API.
    #
    # Fiber-scoped via ActiveSupport::IsolatedExecutionState rather than
    # Thread.current, so it survives the places Rails hands work to a fiber —
    # streaming responses, async adapters — instead of silently reverting to
    # the global halfway through a request.
    #
    # Nesting restores the enclosing scope, not the global.
    def with_credentials(credentials = nil, **attributes)
      resolved = credentials || (Credentials.new(**attributes) unless attributes.empty?)

      return yield if resolved.nil?

      previous = ActiveSupport::IsolatedExecutionState[:clowk_credentials]
      ActiveSupport::IsolatedExecutionState[:clowk_credentials] = resolved

      yield
    ensure
      ActiveSupport::IsolatedExecutionState[:clowk_credentials] = previous if resolved
    end
  end
end
