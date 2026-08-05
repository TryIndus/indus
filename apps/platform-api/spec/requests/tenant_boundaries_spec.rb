require "rails_helper"

RSpec.describe "tenant API boundaries", type: :request do
  let(:claims) { { "iss" => "https://example.supabase.co/auth/v1", "sub" => "current-user", "email" => "user@example.test" } }
  let(:verifier) { instance_double(Authentication::TokenVerifier, verify: claims) }
  let(:headers) { { "Authorization" => "Bearer valid-test-token", "Idempotency-Key" => SecureRandom.uuid } }

  before { allow(Authentication).to receive(:verifier).and_return(verifier) }

  it "rejects requests without a bearer token" do
    get "/v1/favorites"
    expect(response).to have_http_status(:unauthorized)
    expect(response.media_type).to eq("application/problem+json")
    expect(JSON.parse(response.body).keys).to include("type", "title", "status", "code", "request_id")
    expect(verifier).not_to have_received(:verify)
  end

  it "rejects idempotency keys outside the contract format" do
    [ "short", "x" * 129, "invalid key value" ].each do |key|
      post "/v1/favorites", params: { symbol: "AAPL", instrument_type: "equity" },
        headers: { "Authorization" => "Bearer valid-test-token", "Idempotency-Key" => key }
      expect(response).to have_http_status(:bad_request)
    end
    expect(Favorite.count).to eq(0)
  end

  it "requires an idempotency key for authenticated mutations" do
    post "/v1/favorites", params: { symbol: "AAPL", instrument_type: "equity" },
      headers: { "Authorization" => "Bearer valid-test-token" }
    expect(response).to have_http_status(:bad_request)
    expect(Favorite.count).to eq(0)
  end

  it "normalizes and creates a favorite for the authenticated tenant" do
    post "/v1/favorites", params: { symbol: " aapl ", instrument_type: "equity" }, headers: headers
    expect(response).to have_http_status(:created)
    expect(JSON.parse(response.body)).to include("symbol" => "AAPL")
    expect(User.find_by!(external_subject: "current-user").favorites.pluck(:symbol)).to eq([ "AAPL" ])
  end

  it "does not expose another tenant's portfolio" do
    other = User.create!(issuer: claims["iss"], external_subject: "other-user", email: "other@example.test", display_name: "Other")
    portfolio = other.portfolios.create!(name: "Private")
    get "/v1/portfolios/#{portfolio.id}", headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it "writes a report and outbox event atomically" do
    expect do
      post "/v1/reports", params: { symbol: "msft" }, headers: headers
    end.to change(Report, :count).by(1).and change(OutboxEvent, :count).by(1)
    expect(response).to have_http_status(:accepted)
    expect(OutboxEvent.last.payload).to include("symbol" => "MSFT")
    expect(AuditEvent.last.attributes).to include("action" => "reports.create", "resource_type" => "Report",
      "resource_id" => Report.last.id)
  end

  it "replays the same write without duplicating side effects or audit events" do
    expect do
      post "/v1/reports", params: { symbol: "MSFT" }, headers: headers
      @original_response = JSON.parse(response.body)
      post "/v1/reports", params: { symbol: "MSFT" }, headers: headers
    end.to change(Report, :count).by(1).and change(OutboxEvent, :count).by(1).and change(AuditEvent, :count).by(1)
    expect(response).to have_http_status(:accepted)
    expect(response.headers["Idempotency-Replayed"]).to eq("true")
    expect(JSON.parse(response.body)).to eq(@original_response)
  end

  it "rejects a changed request that reuses an idempotency key" do
    post "/v1/reports", params: { symbol: "MSFT" }, headers: headers
    expect do
      post "/v1/reports", params: { symbol: "AAPL" }, headers: headers
    end.not_to change(Report, :count)
    expect(response).to have_http_status(:conflict)
    expect(JSON.parse(response.body)).to include("code" => "idempotency_conflict", "status" => 409)
  end

  it "replays an empty delete response without repeating the deletion" do
    user = User.find_or_create_by!(issuer: claims["iss"], external_subject: claims["sub"]) do |record|
      record.email = claims["email"]
      record.display_name = "Current User"
    end
    favorite = user.favorites.create!(symbol: "AAPL")
    expect do
      delete "/v1/favorites/AAPL?instrument_type=equity", headers: headers
      delete "/v1/favorites/AAPL?instrument_type=equity", headers: headers
    end.to change(Favorite, :count).by(-1).and change(AuditEvent, :count).by(1)
    expect(response).to have_http_status(:no_content)
    expect(response.body).to eq("")
    expect(response.headers["Idempotency-Replayed"]).to eq("true")
  end

  it "does not write an outbox event when report validation fails" do
    audit_count = AuditEvent.count
    expect do
      post "/v1/reports", params: { symbol: "not a symbol" }, headers: headers
    end.not_to change(OutboxEvent, :count)
    expect(AuditEvent.count).to eq(audit_count)
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "returns the bounded market contract when a provider is unavailable" do
    provider = instance_double(FundamentalsProvider)
    allow(provider).to receive(:fetch).and_raise(FundamentalsProvider::Error)
    allow(FundamentalsProvider).to receive(:default).and_return(provider)
    get "/v1/market/summary", headers: headers
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to eq("indices" => [], "watchlist" => [])
  end

  it "returns a bounded bad-request response for missing model parameters" do
    post "/v1/explanations", params: { symbol: "AAPL" }, headers: headers
    expect(response).to have_http_status(:bad_request)
    expect(JSON.parse(response.body)).to include("code" => "bad_request", "status" => 400)
  end

  it "does not expose model provider errors" do
    gateway = instance_double(ModelGateway)
    allow(gateway).to receive(:execute).and_raise(ModelGateway::Error.new(:unavailable, "sensitive provider detail"))
    allow(ModelGateway).to receive(:default).and_return(gateway)
    post "/v1/explanations", params: { symbol: "AAPL", metrics: [ "revenue" ] }, headers: headers
    expect(response).to have_http_status(:bad_gateway)
    expect(JSON.parse(response.body)).to include("code" => "upstream_unavailable", "status" => 502)
    expect(response.body).not_to include("sensitive provider detail")
  end
end
