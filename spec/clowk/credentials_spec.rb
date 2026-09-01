# frozen_string_literal: true

RSpec.describe Clowk::Credentials do
  describe "the value object" do
    it "leaves every member optional, because a publishable key alone is the common case" do
      credentials = described_class.new(publishable_key: "pk_test_alpha")

      expect(credentials.publishable_key).to eq("pk_test_alpha")
      expect(credentials.secret_key).to be_nil
      expect(credentials.subdomain_url).to be_nil
      expect(credentials.jwks_url).to be_nil
    end

    # The whole reason audience travels with the credentials rather than being
    # read off the global: a scoped publishable key checked against a global
    # audience verifies one tenant's token against another's expectation.
    it "derives the audience from its own publishable key" do
      expect(described_class.new(publishable_key: "pk_test_alpha").audience).to eq("pk_test_alpha")
    end

    it "keeps an explicit audience" do
      credentials = described_class.new(publishable_key: "pk_test_alpha", audience: "other")

      expect(credentials.audience).to eq("other")
    end

    it "lets false switch the check off" do
      expect(described_class.new(publishable_key: "pk_test_alpha", audience: false).audience).to be(false)
    end

    # Derived at construction and not on read, so the object cannot disagree
    # with itself: to_h and == see the same value callers do.
    it "carries the derived audience into to_h" do
      expect(described_class.new(publishable_key: "pk_test_alpha").to_h[:audience]).to eq("pk_test_alpha")
    end

    # A Struct rather than a Data so the gem still runs on Ruby 3.1, which means
    # the immutability Data gave for free is hand-made here — and it has to
    # hold, because credentials are installed into a scope and read from four
    # places while a request runs.
    it "is frozen, so nothing can reassign a member mid-request" do
      credentials = described_class.new(publishable_key: "pk_test_alpha")

      expect(credentials).to be_frozen
      expect { credentials.publishable_key = "pk_test_other" }.to raise_error(FrozenError)
    end

    it "builds from the boot configuration" do
      Clowk.config.publishable_key = "pk_test_boot"

      credentials = described_class.from(Clowk.config)

      expect(credentials.publishable_key).to eq("pk_test_boot")
      expect(credentials.secret_key).to eq("spec_secret_key")
      expect(credentials.subdomain_url).to eq("https://acme.clowk.dev")
    end
  end

  describe "Clowk.credentials" do
    it "falls back to the boot configuration when nothing is scoped" do
      Clowk.config.publishable_key = "pk_test_boot"

      expect(Clowk.credentials.publishable_key).to eq("pk_test_boot")
      expect(Clowk.credentials.subdomain_url).to eq("https://acme.clowk.dev")
    end
  end

  describe "Clowk.with_credentials" do
    let(:scoped) do
      described_class.new(publishable_key: "pk_test_tenant", secret_key: "tenant_secret",
        subdomain_url: "https://tenant.clowk.dev")
    end

    it "puts the given credentials in force for the block" do
      Clowk.with_credentials(scoped) do
        expect(Clowk.credentials.publishable_key).to eq("pk_test_tenant")
        expect(Clowk.credentials.secret_key).to eq("tenant_secret")
      end
    end

    it "restores the previous credentials afterwards" do
      Clowk.config.publishable_key = "pk_test_boot"

      Clowk.with_credentials(scoped) { nil }

      expect(Clowk.credentials.publishable_key).to eq("pk_test_boot")
    end

    # The reason this is a block and not a setter. A setter has no lifetime, so
    # the first request that raises between assignment and reset leaves one
    # tenant's secret_key installed process-wide — and that key mints HS256
    # tokens for any subject, on the path that does not check the audience.
    it "restores them even when the block raises" do
      Clowk.config.publishable_key = "pk_test_boot"

      expect { Clowk.with_credentials(scoped) { raise "boom" } }.to raise_error("boom")

      expect(Clowk.credentials.publishable_key).to eq("pk_test_boot")
    end

    it "restores the enclosing scope when nested, not the global" do
      inner = described_class.new(publishable_key: "pk_test_inner")

      Clowk.with_credentials(scoped) do
        Clowk.with_credentials(inner) do
          expect(Clowk.credentials.publishable_key).to eq("pk_test_inner")
        end

        expect(Clowk.credentials.publishable_key).to eq("pk_test_tenant")
      end
    end

    it "returns whatever the block returns" do
      expect(Clowk.with_credentials(scoped) { :done }).to eq(:done)
    end
  end

  # The point of the whole change: the parts that name an instance have to read
  # the scoped credentials, or scoping them would be decoration.
  describe "what reads them" do
    let(:scoped) do
      described_class.new(publishable_key: "pk_test_tenant", secret_key: "tenant_secret",
        subdomain_url: "https://tenant.clowk.dev")
    end

    it "is picked up by the JWT verifier" do
      Clowk.with_credentials(scoped) do
        verifier = Clowk::JwtVerifier.new

        expect(verifier.instance_variable_get(:@secret_key)).to eq("tenant_secret")
        expect(verifier.instance_variable_get(:@audience)).to eq("pk_test_tenant")
      end
    end

    # Without a publishable key, because Subdomain#resolve_url! prefers the key
    # and resolves it over the network — the scoped subdomain_url is what is
    # under test here, not the resolution order.
    it "is picked up by the subdomain resolver" do
      subdomain_only = described_class.new(subdomain_url: "https://tenant.clowk.dev")

      Clowk.with_credentials(subdomain_only) do
        expect(Clowk::Subdomain.resolve_url!).to eq("https://tenant.clowk.dev")
      end
    end

    it "is picked up by the JWKS url" do
      Clowk.with_credentials(scoped) do
        expect(Clowk::Jwks.default_url).to eq("https://tenant.clowk.dev/.well-known/jwks.json")
      end
    end

    it "is picked up by the SDK client" do
      Clowk.with_credentials(scoped) do
        client = Clowk::SDK::Client.new

        expect(client.instance_variable_get(:@secret_key)).to eq("tenant_secret")
        expect(client.instance_variable_get(:@publishable_key)).to eq("pk_test_tenant")
      end
    end

    # Explicit arguments still win, so every existing caller keeps working.
    it "yields to an explicitly passed value" do
      Clowk.with_credentials(scoped) do
        client = Clowk::SDK::Client.new(secret_key: "explicit")

        expect(client.instance_variable_get(:@secret_key)).to eq("explicit")
      end
    end
  end

  # One name to remember, and it never makes the caller reach for the class.
  describe "calling it with plain attributes" do
    it "builds the credentials from keywords" do
      Clowk.with_credentials(publishable_key: "pk_test_tenant", secret_key: "tenant_secret") do
        expect(Clowk.credentials.publishable_key).to eq("pk_test_tenant")
        expect(Clowk.credentials.secret_key).to eq("tenant_secret")
        expect(Clowk.credentials.audience).to eq("pk_test_tenant")
      end
    end

    it "restores the previous credentials afterwards" do
      Clowk.config.publishable_key = "pk_test_boot"

      Clowk.with_credentials(publishable_key: "pk_test_tenant") { nil }

      expect(Clowk.credentials.publishable_key).to eq("pk_test_boot")
    end

    # So "this request has no tenant" needs no branch at the call site.
    it "runs the block against the boot configuration when given nil" do
      Clowk.config.publishable_key = "pk_test_boot"

      Clowk.with_credentials(nil) do
        expect(Clowk.credentials.publishable_key).to eq("pk_test_boot")
      end
    end

    it "leaves an enclosing scope alone when given nil" do
      Clowk.with_credentials(publishable_key: "pk_test_outer") do
        Clowk.with_credentials(nil) do
          expect(Clowk.credentials.publishable_key).to eq("pk_test_outer")
        end

        expect(Clowk.credentials.publishable_key).to eq("pk_test_outer")
      end
    end

    it "returns whatever the block returns" do
      expect(Clowk.with_credentials(publishable_key: "pk_x") { :rendered }).to eq(:rendered)
      expect(Clowk.with_credentials(nil) { :rendered }).to eq(:rendered)
    end
  end

  describe "Clowk.reset!" do
    it "clears a scoped override that outlived its block" do
      ActiveSupport::IsolatedExecutionState[:clowk_credentials] =
        described_class.new(publishable_key: "pk_test_leaked")

      Clowk.reset!

      expect(Clowk.credentials.publishable_key).to be_nil
    end
  end
end
