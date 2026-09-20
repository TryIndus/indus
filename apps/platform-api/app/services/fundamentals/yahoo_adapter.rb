require "net/http"
require "timeout"

module Fundamentals
  class YahooAdapter < FundamentalsProvider
    ENDPOINT = "https://query1.finance.yahoo.com/v7/finance/spark".freeze
    TIMESERIES_ENDPOINT = "https://query1.finance.yahoo.com/ws/fundamentals-timeseries/v1/finance/timeseries".freeze
    MAX_BATCH_SIZE = 25
    DEFAULT_TIMEOUT = 10
    TIMESERIES_METRICS = {
      "trailingMarketCap" => "market_cap",
      "trailingPeRatio" => "trailing_pe_ratio",
      "trailingTotalRevenue" => "revenue_ttm",
      "trailingGrossProfit" => "gross_profit_ttm",
      "trailingOperatingIncome" => "operating_income_ttm",
      "trailingNetIncome" => "net_income_ttm",
      "trailingEBITDA" => "ebitda_ttm",
      "trailingDilutedEPS" => "diluted_eps_ttm",
      "trailingOperatingCashFlow" => "operating_cash_flow_ttm",
      "trailingFreeCashFlow" => "free_cash_flow_ttm",
      "quarterlyTotalAssets" => "total_assets",
      "quarterlyTotalDebt" => "total_debt",
      "quarterlyStockholdersEquity" => "stockholders_equity",
      "quarterlyCashAndCashEquivalents" => "cash_and_equivalents",
      "quarterlyCurrentAssets" => "current_assets",
      "quarterlyCurrentLiabilities" => "current_liabilities"
    }.freeze

    def initialize(transport: Net::HTTP) = @transport = transport

    def fetch(symbol:)
      normalized = normalized_symbol(symbol)
      snapshot = fetch_many(symbols: [ normalized ], timeout: DEFAULT_TIMEOUT).fetch(normalized)
      enrich(snapshot)
    rescue KeyError
      raise NotFound, "symbol not found"
    end

    def fetch_many(symbols:, timeout:)
      normalized = symbols.map { |symbol| normalized_symbol(symbol) }.uniq
      raise Error, "fundamentals batch is empty" if normalized.empty?
      raise Error, "fundamentals batch is too large" if normalized.length > MAX_BATCH_SIZE
      timeout = Float(timeout)
      raise Error, "fundamentals provider deadline exceeded" unless timeout.positive?

      uri = URI(ENDPOINT)
      uri.query = URI.encode_www_form(symbols: normalized.join(","), range: "1d", interval: "1d")
      request = Net::HTTP::Get.new(uri, { "Accept" => "application/json", "User-Agent" => "Indus/1.0" })
      response = Timeout.timeout(timeout) do
        @transport.start(uri.host, uri.port, use_ssl: true, open_timeout: [ 3, timeout ].min,
          read_timeout: [ DEFAULT_TIMEOUT, timeout ].min) do |http|
          http.request(request)
        end
      end
      raise Error, "fundamentals provider unavailable" unless response.is_a?(Net::HTTPSuccess)

      quotes = JSON.parse(response.body).dig("spark", "result")
      raise Error, "fundamentals provider returned invalid data" unless quotes.is_a?(Array)

      as_of = Time.current
      quotes.filter_map do |quote|
        symbol = quote["symbol"].to_s.upcase
        next unless normalized.include?(symbol)
        meta = quote.dig("response", 0, "meta")
        next unless meta.is_a?(Hash)

        [ symbol, FundamentalsSnapshot.new(symbol: symbol, as_of: as_of,
          metrics: meta.slice("regularMarketPrice", "regularMarketChangePercent", "regularMarketDayHigh",
            "regularMarketDayLow", "regularMarketVolume", "fiftyTwoWeekHigh", "fiftyTwoWeekLow", "shortName"),
          source_reference: "yahoo:spark:#{symbol}") ]
      end.to_h
    rescue ArgumentError, JSON::ParserError, SocketError, SystemCallError, Timeout::Error => error
      raise Error, "fundamentals provider failed: #{error.class}"
    end

    private

    def enrich(snapshot)
      uri = URI("#{TIMESERIES_ENDPOINT}/#{URI.encode_www_form_component(snapshot.symbol)}")
      uri.query = URI.encode_www_form(
        type: TIMESERIES_METRICS.keys.join(","),
        period1: 5.years.ago.to_i,
        period2: Time.current.to_i
      )
      request = Net::HTTP::Get.new(uri, { "Accept" => "application/json", "User-Agent" => "Indus/1.0" })
      response = Timeout.timeout(DEFAULT_TIMEOUT) do
        @transport.start(uri.host, uri.port, use_ssl: true, open_timeout: 3, read_timeout: DEFAULT_TIMEOUT) do |http|
          http.request(request)
        end
      end
      raise Error, "fundamentals timeseries unavailable" unless response.is_a?(Net::HTTPSuccess)

      rows = JSON.parse(response.body).dig("timeseries", "result")
      raise Error, "fundamentals timeseries returned invalid data" unless rows.is_a?(Array)

      metrics = rows.each_with_object({}) do |row, result|
        provider_key = TIMESERIES_METRICS.keys.find { |key| row[key].is_a?(Array) }
        next unless provider_key

        value = row[provider_key].last&.dig("reportedValue", "raw")
        result[TIMESERIES_METRICS.fetch(provider_key)] = value if value.is_a?(Numeric)
      end
      add_derived_metrics!(metrics)

      FundamentalsSnapshot.new(symbol: snapshot.symbol, as_of: snapshot.as_of,
        metrics: snapshot.metrics.merge(metrics), source_reference: snapshot.source_reference)
    rescue Error, ArgumentError, JSON::ParserError, SocketError, SystemCallError, Timeout::Error => error
      Rails.logger.warn(event: "fundamentals_timeseries_unavailable", symbol: snapshot.symbol,
        error_class: error.class.name)
      snapshot
    end

    def add_derived_metrics!(metrics)
      metrics["gross_margin"] = ratio(metrics["gross_profit_ttm"], metrics["revenue_ttm"])
      metrics["operating_margin"] = ratio(metrics["operating_income_ttm"], metrics["revenue_ttm"])
      metrics["net_margin"] = ratio(metrics["net_income_ttm"], metrics["revenue_ttm"])
      metrics["current_ratio"] = ratio(metrics["current_assets"], metrics["current_liabilities"])
      metrics["debt_to_equity"] = ratio(metrics["total_debt"], metrics["stockholders_equity"])
      metrics.compact!
    end

    def ratio(numerator, denominator)
      return unless numerator.is_a?(Numeric) && denominator.is_a?(Numeric) && !denominator.zero?

      numerator.fdiv(denominator)
    end

    def normalized_symbol(symbol)
      normalized = symbol.to_s.upcase
      valid = normalized.match?(/\A[A-Z0-9]+(?:[.\/-][A-Z0-9]+)?\z/) && normalized.length <= 20
      raise InvalidSymbol, "invalid symbol" unless valid

      normalized
    end
  end
end
