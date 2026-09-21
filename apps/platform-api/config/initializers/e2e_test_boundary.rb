# This boundary is available only to the disposable full-stack browser suite. It
# replaces network identity and market providers while leaving the browser,
# HTTP, authorization, persistence, idempotency, and serialization paths real.
if Rails.env.test? && ENV["E2E_TEST_BOUNDARY"] == "true"
  Rails.application.config.to_prepare do
    expected_token = ENV.fetch("E2E_ACCESS_TOKEN")
    verifier = Class.new do
      define_method(:initialize) { |token| @token = token }

      define_method(:verify) do |token|
        unless token.bytesize == @token.bytesize && ActiveSupport::SecurityUtils.secure_compare(token, @token)
          raise Authentication::Unauthorized, "invalid end-to-end test token"
        end

        {
          "iss" => "https://identity.indus.test/e2e",
          "sub" => "playwright-user",
          "email" => "investor@example.test",
          "name" => "Playwright Investor"
        }
      end
    end.new(expected_token)

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

    Authentication.verifier = verifier
    FundamentalsProvider.define_singleton_method(:default) { provider }
    MarketHistory::YahooAdapter.define_singleton_method(:new) { history_provider }
  end
end
