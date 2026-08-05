require "rails_helper"

RSpec.describe MarketSummary do
  it "normalizes provider snapshots into the web contract" do
    provider = instance_double(FundamentalsProvider)
    allow(provider).to receive(:fetch) do |symbol:|
      FundamentalsSnapshot.new(symbol: symbol, as_of: Time.current,
        metrics: { "regularMarketPrice" => 100.5, "regularMarketChangePercent" => 1.25, "shortName" => "Name #{symbol}" },
        source_reference: "fixture:#{symbol}")
    end

    result = described_class.new(watchlist: %w[AAPL MSFT NVDA], provider: provider).call
    expect(result[:indices]).to all(include(:symbol, price: 100.5, changePercent: 1.25))
    expect(result[:watchlist]).to all(include(:symbol, :name, price: 100.5, changePercent: 1.25))
    expect(provider).to have_received(:fetch).exactly(6).times
  end

  it "returns bounded empty collections when providers are unavailable" do
    provider = instance_double(FundamentalsProvider)
    allow(provider).to receive(:fetch).and_raise(FundamentalsProvider::Error)
    expect(described_class.new(provider: provider).call).to eq(indices: [], watchlist: [])
  end
end
