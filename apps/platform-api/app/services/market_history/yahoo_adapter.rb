require "net/http"
require "timeout"

module MarketHistory
  Snapshot = Data.define(:symbol, :currency, :points)

  class YahooAdapter
    ENDPOINT = "https://query1.finance.yahoo.com/v8/finance/chart".freeze
    DEFAULT_TIMEOUT = 10
    MAX_POINTS = 400

    def initialize(transport: Net::HTTP) = @transport = transport

    def fetch(symbol:)
      normalized = normalized_symbol(symbol)
      uri = URI("#{ENDPOINT}/#{URI.encode_www_form_component(normalized)}")
      uri.query = URI.encode_www_form(range: "1y", interval: "1d", events: "history")
      request = Net::HTTP::Get.new(uri, { "Accept" => "application/json", "User-Agent" => "Indus/1.0" })
      response = Timeout.timeout(DEFAULT_TIMEOUT) do
        @transport.start(uri.host, uri.port, use_ssl: true, open_timeout: 3, read_timeout: DEFAULT_TIMEOUT) do |http|
          http.request(request)
        end
      end
      raise FundamentalsProvider::Error, "market history provider unavailable" unless response.is_a?(Net::HTTPSuccess)

      result = JSON.parse(response.body).dig("chart", "result", 0)
      raise FundamentalsProvider::NotFound, "symbol history not found" unless result.is_a?(Hash)

      timestamps = result["timestamp"]
      closes = result.dig("indicators", "quote", 0, "close")
      unless timestamps.is_a?(Array) && closes.is_a?(Array) && timestamps.length == closes.length
        raise FundamentalsProvider::Error, "market history provider returned invalid data"
      end

      points = timestamps.zip(closes).last(MAX_POINTS).filter_map do |timestamp, close|
        next unless timestamp.is_a?(Numeric) && close.is_a?(Numeric) && close.finite?

        { timestamp: Time.at(timestamp).utc.iso8601, close: close }
      end
      raise FundamentalsProvider::NotFound, "symbol history not found" if points.empty?

      currency = result.dig("meta", "currency").to_s.upcase
      currency = "USD" unless currency.match?(/\A[A-Z]{3}\z/)
      Snapshot.new(symbol: normalized, currency: currency, points: points)
    rescue JSON::ParserError, SocketError, SystemCallError, Timeout::Error => error
      raise FundamentalsProvider::Error, "market history provider failed: #{error.class}"
    end

    private

    def normalized_symbol(symbol)
      normalized = symbol.to_s.upcase
      valid = normalized.match?(/\A[A-Z0-9]+(?:[.\/-][A-Z0-9]+)?\z/) && normalized.length <= 20
      raise FundamentalsProvider::InvalidSymbol, "invalid symbol" unless valid

      normalized
    end
  end
end
