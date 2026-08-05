class MarketSummary
  INDICES = %w[SPY DIA QQQ].freeze
  def initialize(watchlist: [], provider: FundamentalsProvider.default)
    @watchlist = watchlist.first(100)
    @provider = provider
  end

  def call
    { indices: snapshots(INDICES, include_name: false),
      watchlist: snapshots(@watchlist.map { |favorite| favorite.respond_to?(:symbol) ? favorite.symbol : favorite }, include_name: true) }
  end

  private

  def snapshots(symbols, include_name:)
    symbols.filter_map do |symbol|
      snapshot = @provider.fetch(symbol: symbol)
      metrics = snapshot.metrics
      price = metrics["regularMarketPrice"]
      change = metrics["regularMarketChangePercent"]
      next unless price && change

      item = { symbol: symbol, price: price, changePercent: change }
      item[:name] = metrics["shortName"] || symbol if include_name
      item if item[:price]
    rescue FundamentalsProvider::Error
      nil
    end
  end
end
