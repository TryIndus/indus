require "rails_helper"

RSpec.describe Fundamentals::YahooAdapter do
  class FakeFundamentalsTransport
    attr_reader :request

    def initialize(body:) = @body = body

    def start(*)
      http = Object.new
      owner = self
      http.define_singleton_method(:request) do |request|
        owner.instance_variable_set(:@request, request)
        response = Net::HTTPOK.new("1.1", "200", "OK")
        response.instance_variable_set(:@read, true)
        response.body = owner.instance_variable_get(:@body)
        response
      end
      yield http
    end
  end

  it "normalizes a bounded quote fixture" do
    transport = FakeFundamentalsTransport.new(body: file_fixture("yahoo_quote_success.json").read)
    snapshot = described_class.new(transport: transport).fetch(symbol: "aapl")
    expect(snapshot.to_h).to include(symbol: "AAPL", source_reference: "yahoo:quote:AAPL",
      metrics: include("regularMarketPrice" => 218.27, "shortName" => "Apple Inc."))
    expect(transport.request["User-Agent"]).to eq("Indus/1.0")
  end

  it "rejects malformed symbols before making a provider request" do
    transport = instance_double(Class)
    expect { described_class.new(transport: transport).fetch(symbol: "bad symbol") }
      .to raise_error(FundamentalsProvider::Error, /invalid symbol/)
  end
end
