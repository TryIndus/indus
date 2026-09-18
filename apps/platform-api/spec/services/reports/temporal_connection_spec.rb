require "rails_helper"

RSpec.describe Reports::TemporalConnection do
  around do |example|
    names = %w[TEMPORAL_ADDRESS TEMPORAL_NAMESPACE TEMPORAL_API_KEY TEMPORAL_AUTH_MODE]
    original = ENV.to_h.slice(*names)
    names.each { |name| ENV.delete(name) }
    example.run
  ensure
    names.each { |name| ENV.delete(name) }
    original.each { |name, value| ENV[name] = value }
  end

  before { allow(Temporalio::Client).to receive(:connect) }

  it "keeps disposable local Temporal connections available" do
    described_class.connect
    expect(Temporalio::Client).to have_received(:connect).with("temporal:7233", "default")
  end

  it "always enables TLS when passing an API key" do
    ENV.update("TEMPORAL_AUTH_MODE" => "api_key", "TEMPORAL_ADDRESS" => "example.tmprl.cloud:7233",
      "TEMPORAL_NAMESPACE" => "staging.example", "TEMPORAL_API_KEY" => "test-key")
    described_class.connect
    expect(Temporalio::Client).to have_received(:connect).with("example.tmprl.cloud:7233",
      "staging.example", api_key: "test-key", tls: true)
  end

  %w[TEMPORAL_ADDRESS TEMPORAL_NAMESPACE TEMPORAL_API_KEY].each do |missing|
    it "rejects missing #{missing} before opening a connection" do
      ENV.update("TEMPORAL_AUTH_MODE" => "api_key", "TEMPORAL_ADDRESS" => "example.tmprl.cloud:7233",
        "TEMPORAL_NAMESPACE" => "staging.example", "TEMPORAL_API_KEY" => "test-key")
      ENV[missing] = " "
      expect { described_class.connect }.to raise_error(ArgumentError, /#{missing} is required/)
      expect(Temporalio::Client).not_to have_received(:connect)
    end
  end

  it "rejects Cloud endpoints in local mode" do
    ENV["TEMPORAL_ADDRESS"] = "example.tmprl.cloud:7233"
    expect { described_class.connect }.to raise_error(ArgumentError, /TEMPORAL_AUTH_MODE/)
    expect(Temporalio::Client).not_to have_received(:connect)
  end

  it "does not silently ignore a credential in local mode" do
    ENV["TEMPORAL_API_KEY"] = "test-key"
    expect { described_class.connect }.to raise_error(ArgumentError, /TEMPORAL_AUTH_MODE/)
    expect(Temporalio::Client).not_to have_received(:connect)
  end

  it "rejects unsupported authentication modes" do
    ENV["TEMPORAL_AUTH_MODE"] = "unknown"
    expect { described_class.connect }.to raise_error(ArgumentError, /must be local or api_key/)
  end
end
