require "rails_helper"

RSpec.describe Instruments::YahooSearchAdapter do
  class FakeSearchTransport
    def initialize(body) = @body = body

    def start(*)
      body = @body
      http = Object.new
      http.define_singleton_method(:request) do |_request|
        response = Net::HTTPOK.new("1.1", "200", "OK")
        response.instance_variable_set(:@read, true)
        response.body = body
        response
      end
      yield http
    end
  end

  it "omits an absent exchange rather than returning a contract-invalid null" do
    body = { quotes: [ { symbol: "AAPL", shortname: "Apple Inc.", quoteType: "EQUITY" } ] }.to_json
    result = described_class.new(transport: FakeSearchTransport.new(body)).search(query: "apple", limit: 5)
    expect(result).to eq([ { symbol: "AAPL", name: "Apple Inc.", instrument_type: "equity" } ])
    expect(result.first).not_to have_key(:exchange)
  end
end
