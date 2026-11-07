# frozen_string_literal: true

require "digest"

module Clowk
  # Exchanges and refreshes session tokens, one refresh per refresh token.
  #
  # Refresh tokens rotate: each one works once. A page and its Turbo frames
  # can arrive together with the same expired access token, and each would
  # spend the same refresh token. Only the first wins, and the rest would sign
  # the user out. The first request takes a lock in the cache and shares the
  # new pair; the others wait for it and use the same pair.
  #
  # The lock works across processes only with a shared cache (Solid Cache,
  # Redis, Memcached). With a per-process cache, Clowk's grace window for a
  # just-rotated token keeps the session alive, and the late request is
  # signed in again on the next request.
  class TokenRefresher
    LOCK_TTL = 10
    RESULT_TTL = 30
    WAIT_TIMEOUT = 5.0
    WAIT_INTERVAL = 0.05

    def initialize(cache: Clowk.config.session_status_cache, client: nil)
      @cache = cache
      @client = client
    end

    # @return [Hash, nil] the pair, or nil when no publishable key is set
    # @raise [Clowk::InvalidTokenError] when Clowk refuses the token
    def exchange(token)
      return unless publishable_key?

      sdk.session_tokens.exchange(token: token)
    end

    # @return [Hash] the new pair
    # @raise [Clowk::InvalidTokenError] when Clowk refuses the refresh token
    def refresh(refresh_token)
      key = Digest::SHA256.hexdigest(refresh_token.to_s)

      shared = read_shared(key)

      return shared if shared

      return rotate(refresh_token, key) if acquire_lock(key)

      wait_for_shared(key) || raise(Clowk::InvalidTokenError, "concurrent refresh did not finish")
    end

    # Ends the session on Clowk. Best effort: a sign-out must not fail because
    # the broker is down.
    def revoke(refresh_token)
      return if refresh_token.blank? || !publishable_key?

      sdk.session_tokens.revoke(refresh_token: refresh_token)
    rescue Clowk::Error, *Clowk::Authenticable::BROKER_UNAVAILABLE
      nil
    end

    private

    attr_reader :cache

    def rotate(refresh_token, key)
      pair = sdk.session_tokens.refresh(refresh_token: refresh_token)

      cache&.write(result_key(key), pair, expires_in: RESULT_TTL)

      pair
    rescue Clowk::InvalidTokenError
      cache&.write(result_key(key), {refused: true}, expires_in: RESULT_TTL)

      raise
    ensure
      cache&.delete(lock_key(key))
    end

    def acquire_lock(key)
      return true if cache.nil?

      cache.write(lock_key(key), 1, unless_exist: true, expires_in: LOCK_TTL)
    end

    def wait_for_shared(key)
      deadline = monotonic_now + WAIT_TIMEOUT

      while monotonic_now < deadline
        sleep(WAIT_INTERVAL)

        shared = read_shared(key)

        return shared if shared
      end

      nil
    end

    def read_shared(key)
      shared = cache&.read(result_key(key))&.deep_symbolize_keys

      raise Clowk::InvalidTokenError, "refresh token was refused" if shared&.dig(:refused)

      shared
    end

    def result_key(key)
      "clowk:refresh:result:#{key}"
    end

    def lock_key(key)
      "clowk:refresh:lock:#{key}"
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def publishable_key?
      Clowk.credentials.publishable_key.present?
    end

    def sdk
      @client ||= Clowk::SDK::Client.new
    end
  end
end
