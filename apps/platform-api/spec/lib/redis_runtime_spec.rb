require "spec_helper"
require_relative "../../lib/redis_runtime"

RSpec.describe RedisRuntime do
  let(:clock) { class_double(Time, now: Time.utc(2026, 8, 5, 12, 0, 0)) }

  describe ".connection_options" do
    it "preserves static URL configuration for local runtimes" do
      environment = { "REDIS_URL" => "redis://redis:6379/2" }

      expect(described_class.connection_options(environment)).to eq(url: "redis://redis:6379/2")
    end

    it "defaults local runtimes to the disposable local Redis instance" do
      expect(described_class.connection_options({})).to eq(url: "redis://localhost:6379/0")
    end

    it "builds a verified TLS connection with a callable IAM password" do
      options = described_class.connection_options(iam_environment, signer: fake_signer, clock:)

      expect(options.reject { |key, _value| key == :password }).to eq(
        url: "rediss://cache.example:6380/0",
        username: "indus-production-app",
        ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_PEER },
        reconnect_attempts: [ 0, 0.25, 1 ]
      )
      expect(options.fetch(:password)).to respond_to(:call)
    end

    it "fails closed for an unknown authentication mode" do
      expect { described_class.connection_options({ "REDIS_AUTH_MODE" => "password" }) }
        .to raise_error(RedisRuntime::ConfigurationError, /url or iam/)
    end

    it "fails closed when IAM connection identity is incomplete" do
      environment = iam_environment.reject { |key, _value| key == "REDIS_IAM_USER" }

      expect { described_class.connection_options(environment, signer: fake_signer) }
        .to raise_error(RedisRuntime::ConfigurationError, /REDIS_IAM_USER/)
    end

    it "rejects endpoints containing connection material" do
      environment = iam_environment.merge("REDIS_ENDPOINT" => "rediss://cache.example:6379")

      expect { described_class.connection_options(environment, signer: fake_signer) }
        .to raise_error(RedisRuntime::ConfigurationError, /hostname without a scheme/)
    end
  end

  describe RedisRuntime::IamTokenProvider do
    it "signs a new fifteen-minute serverless token for every connection" do
      signer = instance_double(Aws::Sigv4::Signer)
      allow(signer).to receive(:presign_url)
        .and_return(URI("http://indus-production/?token=first"), URI("http://indus-production/?token=second"))
      provider = described_class.new(
        cache_name: "indus-production",
        username: "indus-production-app",
        region: "ca-central-1",
        signer:,
        clock:
      )

      expect(provider.call("indus-production-app")).to eq("indus-production/?token=first")
      expect(provider.call("indus-production-app")).to eq("indus-production/?token=second")
      expect(signer).to have_received(:presign_url).twice.with(
        http_method: "GET",
        url: "http://indus-production/?Action=connect&ResourceType=ServerlessCache&User=indus-production-app",
        expires_in: 900,
        time: clock.now
      )
    end

    it "creates a deterministic SigV4 token without making a network request" do
      credentials = Aws::Credentials.new("ACCESS_KEY", "secret", "session")
      provider = described_class.new(
        cache_name: "indus-production",
        username: "indus-production-app",
        region: "ca-central-1",
        credentials_provider: credentials,
        clock:
      )

      token = provider.call("indus-production-app")
      query = URI.decode_www_form(URI("http://#{token}").query).to_h

      expect(query).to include(
        "Action" => "connect",
        "ResourceType" => "ServerlessCache",
        "User" => "indus-production-app",
        "X-Amz-Date" => "20260805T120000Z",
        "X-Amz-Expires" => "900",
        "X-Amz-Security-Token" => "session"
      )
      expect(query.fetch("X-Amz-Signature")).to match(/\A[0-9a-f]{64}\z/)
    end

    it "refuses to sign for a different Redis user" do
      provider = described_class.new(
        cache_name: "indus-production",
        username: "indus-production-app",
        region: "ca-central-1",
        signer: fake_signer
      )

      expect { provider.call("another-user") }
        .to raise_error(RedisRuntime::ConfigurationError, /does not match/)
    end
  end

  def iam_environment
    {
      "REDIS_AUTH_MODE" => "iam",
      "REDIS_ENDPOINT" => "cache.example",
      "REDIS_PORT" => "6380",
      "REDIS_IAM_CACHE_NAME" => "indus-production",
      "REDIS_IAM_USER" => "indus-production-app",
      "AWS_REGION" => "ca-central-1"
    }
  end

  def fake_signer
    @fake_signer ||= instance_double(
      Aws::Sigv4::Signer,
      presign_url: URI("http://indus-production/?X-Amz-Signature=signature")
    )
  end
end
