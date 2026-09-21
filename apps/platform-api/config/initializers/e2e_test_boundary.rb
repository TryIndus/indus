# This boundary is available only to the disposable full-stack browser suite. It
# replaces network identity and market providers while leaving the browser,
# HTTP, authorization, persistence, idempotency, and serialization paths real.
if Rails.env.test? && ENV["E2E_TEST_BOUNDARY"] == "true"
  Rails.application.config.to_prepare do
    identities = {
      ENV.fetch("E2E_ACCESS_TOKEN") => {
        "iss" => "https://identity.indus.test/e2e",
        "sub" => "playwright-user",
        "email" => "investor@example.test",
        "name" => "Playwright Investor"
      },
      ENV.fetch("E2E_SECONDARY_ACCESS_TOKEN") => {
        "iss" => "https://identity.indus.test/e2e",
        "sub" => "playwright-secondary-user",
        "email" => "secondary@example.test",
        "name" => "Secondary Investor"
      }
    }
    verifier = Class.new do
      define_method(:initialize) { |tokens| @tokens = tokens }

      define_method(:verify) do |token|
        claims = @tokens.find do |candidate, _claims|
          token.bytesize == candidate.bytesize && ActiveSupport::SecurityUtils.secure_compare(token, candidate)
        end&.last
        if claims.nil?
          raise Authentication::Unauthorized, "invalid end-to-end test token"
        end

        claims
      end
    end.new(identities)

    provider = Class.new(FundamentalsProvider) do
      def fetch(symbol:)
        normalized = symbol.to_s.upcase
        unless normalized.match?(/\A[A-Z0-9]+(?:[.\/-][A-Z0-9]+)?\z/) && normalized.length <= 20
          raise FundamentalsProvider::InvalidSymbol
        end

        FundamentalsSnapshot.new(
          symbol: normalized,
          as_of: Time.zone.parse("2026-09-01T14:30:00Z"),
          metrics: {
            "shortName" => "#{normalized} Holdings",
            "regularMarketPrice" => 200.0,
            "regularMarketChangePercent" => 1.25,
            "marketCap" => 1_000_000_000
          },
          source_reference: "e2e:#{normalized}"
        )
      end

      def fetch_many(symbols:, timeout:)
        raise FundamentalsProvider::Error, "market summary deadline exceeded" unless timeout.positive?

        symbols.to_h { |symbol| [ symbol, fetch(symbol: symbol) ] }
      end
    end.new

    history_provider = Class.new do
      def fetch(symbol:)
        normalized = symbol.to_s.upcase
        unless normalized.match?(/\A[A-Z0-9]+(?:[.\/-][A-Z0-9]+)?\z/) && normalized.length <= 20
          raise FundamentalsProvider::InvalidSymbol
        end

        MarketHistory::Snapshot.new(
          symbol: normalized,
          currency: "USD",
          points: [
            { timestamp: "2026-01-02T21:00:00Z", close: 180.0 },
            { timestamp: "2026-05-01T20:00:00Z", close: 192.5 },
            { timestamp: "2026-09-01T20:00:00Z", close: 200.0 }
          ]
        )
      end
    end.new

    search_provider = Class.new do
      CATALOG = [
        { symbol: "AAPL", name: "Apple Inc.", instrument_type: "equity", exchange: "NASDAQ" },
        { symbol: "BTC/USD", name: "Bitcoin", instrument_type: "crypto", exchange: "Alpaca" }
      ].freeze

      def search(query:, limit:)
        normalized = query.to_s.downcase
        matches = if normalized == "crypto"
          CATALOG.select { |item| item[:instrument_type] == "crypto" }
        else
          CATALOG.select { |item| item[:symbol].downcase.include?(normalized) || item[:name].downcase.include?(normalized) }
        end
        matches.first(limit)
      end
    end.new

    model_gateway = Class.new do
      def execute(task:, input:, evidence:)
        raise ArgumentError, "unsupported end-to-end model task" unless task == "financial_chat"

        symbol = input[:symbol].presence || "The company"
        ModelExecution.new(
          payload: {
            "message" => { "role" => "assistant", "content" => "#{symbol} has an evidence-backed research brief." },
            "sources" => evidence.citations
          },
          model: "e2e-fixture",
          usage: { input_tokens: 20, output_tokens: 8 },
          task: task,
          prompt_version: "v2"
        )
      end
    end.new

    Authentication.verifier = verifier
    FundamentalsProvider.define_singleton_method(:default) { provider }
    MarketHistory::YahooAdapter.define_singleton_method(:new) { history_provider }
    Instruments::YahooSearchAdapter.define_singleton_method(:new) { search_provider }
    ModelGateway.define_singleton_method(:default) { model_gateway }
  end
end
