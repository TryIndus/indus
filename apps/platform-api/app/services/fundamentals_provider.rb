FundamentalsSnapshot = Data.define(:symbol, :as_of, :metrics, :source_reference)

class FundamentalsProvider
  class Error < StandardError; end

  def self.default = Fundamentals::YahooAdapter.new

  def fetch(symbol:) = raise(NotImplementedError)
end
