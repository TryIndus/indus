require "net/http"

module Fundamentals
  class YahooAdapter < FundamentalsProvider
    ENDPOINT = "https://query1.finance.yahoo.com/v7/finance/quote".freeze

    def initialize(transport: Net::HTTP) = @transport = transport

    def fetch(symbol:)
      normalized = symbol.to_s.upcase
      raise Error, "invalid symbol" unless normalized.match?(/\A[A-Z0-9.\/-]{1,20}\z/)

      uri = URI(ENDPOINT)
      uri.query = URI.encode_www_form(symbols: normalized)
      request = Net::HTTP::Get.new(uri, { "Accept" => "application/json", "User-Agent" => "Indus/1.0" })
      response = @transport.start(uri.host, uri.port, use_ssl: true, open_timeout: 3, read_timeout: 10) do |http|
        http.request(request)
      end
      raise Error, "fundamentals provider unavailable" unless response.is_a?(Net::HTTPSuccess)

      quote = JSON.parse(response.body).dig("quoteResponse", "result", 0)
      raise Error, "symbol not found" unless quote

      FundamentalsSnapshot.new(symbol: normalized, as_of: Time.current,
        metrics: quote.slice("marketCap", "trailingPE", "forwardPE", "epsTrailingTwelveMonths", "regularMarketPrice",
          "regularMarketChangePercent", "shortName"),
        source_reference: "yahoo:quote:#{normalized}")
    rescue JSON::ParserError, SocketError, SystemCallError, Timeout::Error => error
      raise Error, "fundamentals provider failed: #{error.class}"
    end
  end
end
