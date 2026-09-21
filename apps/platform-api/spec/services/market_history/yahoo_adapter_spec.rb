require "rails_helper"

RSpec.describe MarketHistory::YahooAdapter do
  class FakeHistoryTransport
    attr_reader :request

    def initialize(body:) = @body = body

    def start(*)
      owner = self
      yield Object.new.tap { |http| http.define_singleton_method(:request) do |request|
        owner.instance_variable_set(:@request, request)
        Net::HTTPOK.new("1.1", "200", "OK").tap do |response|
          response.instance_variable_set(:@read, true)
          response.body = owner.instance_variable_get(:@body)
        end
      end }
    end
  end

  it "returns a bounded normalized year of closing prices" do
    body = { chart: { result: [ { meta: { currency: "USD" }, timestamp: [ 1_700_000_000, 1_700_086_400 ],
      indicators: { quote: [ { close: [ 189.5, 191.25 ] } ] } } ] } }.to_json
    transport = FakeHistoryTransport.new(body: body)

    snapshot = described_class.new(transport: transport).fetch(symbol: "aapl")

    expect(snapshot.symbol).to eq("AAPL")
    expect(snapshot.points).to eq([
      { timestamp: "2023-11-14T22:13:20Z", close: 189.5 },
      { timestamp: "2023-11-15T22:13:20Z", close: 191.25 }
    ])
    expect(URI.decode_www_form(transport.request.uri.query).to_h)
      .to eq("range" => "1y", "interval" => "1d", "events" => "history")
  end

  it "rejects malformed symbols before provider access" do
    expect { described_class.new(transport: instance_double(Class)).fetch(symbol: "bad symbol") }
      .to raise_error(FundamentalsProvider::InvalidSymbol)
  end
end
