require "rails_helper"

RSpec.describe Fundamentals::YahooAdapter do
  class FakeFundamentalsTransport
    attr_reader :requests

    def initialize(body: nil, bodies: nil)
      @bodies = bodies || [ body ]
      @requests = []
    end

    def request = requests.last

    def start(*)
      http = Object.new
      owner = self
      http.define_singleton_method(:request) do |request|
        owner.requests << request
        response = Net::HTTPOK.new("1.1", "200", "OK")
        response.instance_variable_set(:@read, true)
        bodies = owner.instance_variable_get(:@bodies)
        response.body = bodies.length > 1 ? bodies.shift : bodies.first
        response
      end
      yield http
    end
  end

  it "normalizes a bounded quote fixture" do
    body = { spark: { result: [ { symbol: "AAPL", response: [ { meta: {
      regularMarketPrice: 218.27, regularMarketChangePercent: 1.1, shortName: "Apple Inc."
    } } ] } ] } }.to_json
    transport = FakeFundamentalsTransport.new(body: body)
    snapshot = described_class.new(transport: transport).fetch(symbol: "aapl")
    expect(snapshot.to_h).to include(symbol: "AAPL", source_reference: "yahoo:spark:AAPL",
      metrics: include("regularMarketPrice" => 218.27, "shortName" => "Apple Inc."))
    expect(transport.request["User-Agent"]).to eq("Indus/1.0")
  end

  it "adds income, balance-sheet, cash-flow, valuation, and derived metrics" do
    quote = { spark: { result: [ { symbol: "AAPL", response: [ { meta: {
      regularMarketPrice: 218.27, shortName: "Apple Inc."
    } } ] } ] } }.to_json
    timeseries = { timeseries: { result: [
      { trailingMarketCap: [ { reportedValue: { raw: 3_200_000_000_000 } } ] },
      { trailingTotalRevenue: [ { reportedValue: { raw: 400_000_000_000 } } ] },
      { trailingNetIncome: [ { reportedValue: { raw: 100_000_000_000 } } ] },
      { quarterlyCurrentAssets: [ { reportedValue: { raw: 150_000_000_000 } } ] },
      { quarterlyCurrentLiabilities: [ { reportedValue: { raw: 100_000_000_000 } } ] }
    ] } }.to_json
    transport = FakeFundamentalsTransport.new(bodies: [ quote, timeseries ])

    metrics = described_class.new(transport: transport).fetch(symbol: "AAPL").metrics

    expect(metrics).to include("market_cap" => 3_200_000_000_000, "revenue_ttm" => 400_000_000_000,
      "net_income_ttm" => 100_000_000_000, "net_margin" => 0.25, "current_ratio" => 1.5)
    expect(transport.requests.length).to eq(2)
  end

  it "fetches a bounded symbol batch in one provider request" do
    body = { spark: { result: [
      { symbol: "AAPL", response: [ { meta: { regularMarketPrice: 218.27, regularMarketChangePercent: 1.1 } } ] },
      { symbol: "MSFT", response: [ { meta: { regularMarketPrice: 410.0, regularMarketChangePercent: -0.2 } } ] }
    ] } }.to_json
    transport = FakeFundamentalsTransport.new(body: body)

    snapshots = described_class.new(transport: transport).fetch_many(symbols: %w[aapl MSFT], timeout: 2)

    expect(snapshots.keys).to contain_exactly("AAPL", "MSFT")
    expect(URI.decode_www_form(transport.request.uri.query).to_h)
      .to eq("symbols" => "AAPL,MSFT", "range" => "1d", "interval" => "1d")
  end

  it "rejects malformed symbols before making a provider request" do
    transport = instance_double(Class)
    expect { described_class.new(transport: transport).fetch(symbol: "bad symbol") }
      .to raise_error(FundamentalsProvider::Error, /invalid symbol/)
  end

  it "classifies absent, malformed, and unavailable provider responses" do
    empty = FakeFundamentalsTransport.new(body: '{"spark":{"result":[]}}')
    expect { described_class.new(transport: empty).fetch(symbol: "AAPL") }
      .to raise_error(FundamentalsProvider::NotFound)

    malformed = FakeFundamentalsTransport.new(body: "sensitive upstream payload")
    expect { described_class.new(transport: malformed).fetch(symbol: "AAPL") }
      .to raise_error(FundamentalsProvider::Error, /JSON::ParserError/)

    transport = Class.new do
      def self.start(*) = raise(Timeout::Error)
    end
    expect { described_class.new(transport: transport).fetch(symbol: "AAPL") }
      .to raise_error(FundamentalsProvider::Error, /Timeout::Error/)
  end

  it "rejects non-success HTTP responses without exposing their body" do
    transport = Class.new do
      def self.start(*)
        response = Net::HTTPServiceUnavailable.new("1.1", "503", "Unavailable")
        response.instance_variable_set(:@read, true)
        response.body = "sensitive provider payload"
        yield Object.new.tap { |http| http.define_singleton_method(:request) { |_request| response } }
      end
    end

    expect { described_class.new(transport: transport).fetch(symbol: "AAPL") }
      .to raise_error(FundamentalsProvider::Error, "fundamentals provider unavailable")
  end
end
