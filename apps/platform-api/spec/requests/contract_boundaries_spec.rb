require "rails_helper"

RSpec.describe "OpenAPI product boundaries", type: :request do
  let(:claims) { { "iss" => "https://example.supabase.co/auth/v1", "sub" => "contract-user", "email" => "contract@example.test" } }
  let(:verifier) { instance_double(Authentication::TokenVerifier, verify: claims) }
  let(:auth) { { "Authorization" => "Bearer token" } }
  let(:write_headers) { auth.merge("Idempotency-Key" => SecureRandom.uuid) }

  before { allow(Authentication).to receive(:verifier).and_return(verifier) }

  it "returns and updates the current profile with flat JSON" do
    get "/v1/me", headers: auth
    expect(JSON.parse(response.body)).to include("email" => "contract@example.test", "display_name" => "contract")
    patch "/v1/me", params: { display_name: "Contract User" }, headers: write_headers
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to include("display_name" => "Contract User")
  end

  it "pages favorites using contract fields" do
    post "/v1/favorites", params: { symbol: "BTC/USD", instrument_type: "crypto" }, headers: write_headers
    get "/v1/favorites?page_size=1", headers: auth
    body = JSON.parse(response.body)
    expect(body.keys).to contain_exactly("items", "next_cursor")
    expect(body.fetch("items").first.keys).to contain_exactly("id", "symbol", "instrument_type", "created_at")
  end

  it "creates portfolios and positions from flat decimal-safe bodies" do
    post "/v1/portfolios", params: { name: "Core", base_currency: "USD" }, headers: write_headers
    portfolio = JSON.parse(response.body)
    post "/v1/portfolios/#{portfolio.fetch('id')}/positions",
      params: { symbol: "AAPL", instrument_type: "equity", quantity: "2.5", average_cost: "180.25", currency: "USD" },
      headers: write_headers.merge("Idempotency-Key" => SecureRandom.uuid)
    expect(response).to have_http_status(:created)
    expect(JSON.parse(response.body)).to include("quantity" => "2.5", "average_cost" => "180.25", "currency" => "USD")
  end

  it "returns a normalized fundamentals snapshot" do
    snapshot = FundamentalsSnapshot.new(symbol: "AAPL", as_of: Time.zone.parse("2026-08-05T10:00:00Z"),
      metrics: { "regularMarketPrice" => 200.0 }, source_reference: "fixture:AAPL")
    provider = instance_double(FundamentalsProvider, fetch: snapshot)
    allow(FundamentalsProvider).to receive(:default).and_return(provider)
    get "/v1/fundamentals/AAPL", headers: auth
    expect(JSON.parse(response.body)).to include("symbol" => "AAPL", "source" => "yahoo",
      "metrics" => { "regularMarketPrice" => 200.0 })
  end

  it "returns a bounded instrument search page" do
    search = instance_double(Instruments::YahooSearchAdapter,
      search: [ { symbol: "AAPL", name: "Apple Inc.", instrument_type: "equity", exchange: "NMS" } ])
    allow(Instruments::YahooSearchAdapter).to receive(:new).and_return(search)
    get "/v1/instruments/search?q=apple&page_size=5", headers: auth
    expect(JSON.parse(response.body)).to eq("items" => [ { "symbol" => "AAPL", "name" => "Apple Inc.",
      "instrument_type" => "equity", "exchange" => "NMS" } ], "next_cursor" => nil)
  end

  it "returns batch explanations and chat in their structured contracts" do
    gateway = instance_double(ModelGateway)
    allow(gateway).to receive(:execute).with(task: "metric_explanations", input: hash_including(metrics: [ "revenue" ]))
      .and_return(ModelExecution.new(payload: { "explanations" => [ { "metric" => "revenue", "explanation" => "Revenue grew." } ] },
        model: "fixture", usage: { input_tokens: 4, output_tokens: 3 }, task: "metric_explanations", prompt_version: "v1"))
    allow(gateway).to receive(:execute).with(task: "financial_chat", input: hash_including(:messages))
      .and_return(ModelExecution.new(payload: { "message" => { "role" => "assistant", "content" => "Grounded answer." } },
        model: "fixture", usage: { input_tokens: 5, output_tokens: 2 }, task: "financial_chat", prompt_version: "v1"))
    allow(ModelGateway).to receive(:default).and_return(gateway)

    post "/v1/explanations", params: { symbol: "AAPL", metrics: [ "revenue" ] }, headers: write_headers
    expect(JSON.parse(response.body)).to include("symbol" => "AAPL", "usage" => { "input_tokens" => 4, "output_tokens" => 3 })
    post "/v1/chat", params: { messages: [ { role: "user", content: "Explain revenue" } ] },
      headers: write_headers.merge("Idempotency-Key" => SecureRandom.uuid)
    expect(JSON.parse(response.body).dig("message", "role")).to eq("assistant")
  end

  it "allows the configured local SPA origin without reflecting arbitrary origins" do
    options "/v1/me", headers: { "Origin" => "http://localhost:5173", "Access-Control-Request-Method" => "GET" }
    expect(response.headers["Access-Control-Allow-Origin"]).to eq("http://localhost:5173")
    options "/v1/me", headers: { "Origin" => "https://attacker.example", "Access-Control-Request-Method" => "GET" }
    expect(response.headers["Access-Control-Allow-Origin"]).to be_nil
  end
end
