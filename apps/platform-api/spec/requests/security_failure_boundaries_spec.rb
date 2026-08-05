require "rails_helper"
require "cgi"

RSpec.describe "security and failure boundaries", type: :request do
  let(:claims) { { "iss" => "https://example.supabase.co/auth/v1", "sub" => "boundary-user", "email" => "boundary@example.test" } }
  let(:verifier) { instance_double(Authentication::TokenVerifier, verify: claims) }
  let(:auth) { { "Authorization" => "Bearer token" } }
  let(:key) { "request-boundary-0001" }
  let(:write_headers) { auth.merge("Idempotency-Key" => key) }

  before { allow(Authentication).to receive(:verifier).and_return(verifier) }

  it "rejects verified claims without a valid email before creating a tenant" do
    allow(verifier).to receive(:verify).and_return(claims.merge("email" => "not-an-email"))

    get "/v1/me", headers: auth

    expect(response).to have_http_status(:unauthorized)
    expect(User.where(external_subject: claims.fetch("sub"))).not_to exist
  end

  it "rejects unknown mutation fields before durable side effects" do
    expect do
      post "/v1/reports", params: { symbol: "AAPL", hidden_prompt: "provider secret" }, headers: write_headers
    end.not_to change(Report, :count)

    expect(response).to have_http_status(:bad_request)
    expect(OutboxEvent.count).to eq(0)
    expect(AuditEvent.count).to eq(0)
    expect(IdempotencyRecord.count).to eq(0)
  end

  it "rate limits model work without invoking the provider" do
    user = User.create!(issuer: claims.fetch("iss"), external_subject: claims.fetch("sub"),
      email: claims.fetch("email"), display_name: "Boundary")
    AiUsageWindow.create!(user: user, operation: "explanation", window_started_at: Time.current.beginning_of_hour,
      request_count: ENV.fetch("AI_REQUESTS_PER_HOUR", 30).to_i)
    allow(ModelGateway).to receive(:default)

    post "/v1/explanations", params: { symbol: "AAPL", metrics: [ "revenue" ] }, headers: write_headers

    expect(response).to have_http_status(:too_many_requests)
    expect(response.headers["Retry-After"]).to eq("3600")
    expect(JSON.parse(response.body)).to include("code" => "rate_limited")
    expect(ModelGateway).not_to have_received(:default)
  end

  it "cannot attach a report or position to another tenant's portfolio" do
    other = User.create!(issuer: claims.fetch("iss"), external_subject: "other-boundary-user",
      email: "other@example.test", display_name: "Other")
    portfolio = other.portfolios.create!(name: "Private")

    post "/v1/reports", params: { symbol: "AAPL", portfolio_id: portfolio.id }, headers: write_headers
    expect(response).to have_http_status(:not_found)
    expect(Report.count).to eq(0)
    expect(OutboxEvent.count).to eq(0)

    post "/v1/portfolios/#{portfolio.id}/positions",
      params: { symbol: "AAPL", instrument_type: "equity", quantity: "1", average_cost: "10", currency: "USD" },
      headers: write_headers.merge("Idempotency-Key" => "request-boundary-0002")
    expect(response).to have_http_status(:not_found)
    expect(Position.count).to eq(0)
  end

  it "paginates without duplicating or skipping tenant records" do
    user = User.create!(issuer: claims.fetch("iss"), external_subject: claims.fetch("sub"),
      email: claims.fetch("email"), display_name: "Boundary")
    %w[AAPL MSFT NVDA].each { |symbol| user.favorites.create!(symbol: symbol) }

    get "/v1/favorites?page_size=2", headers: auth
    first = JSON.parse(response.body)
    expect(first.fetch("items").length).to eq(2)
    expect(first.fetch("next_cursor")).to be_present

    get "/v1/favorites?page_size=2&cursor=#{CGI.escape(first.fetch('next_cursor'))}", headers: auth
    second = JSON.parse(response.body)
    expect(second.fetch("items").length).to eq(1)
    expect(second.fetch("next_cursor")).to be_nil
    expect((first.fetch("items") + second.fetch("items")).pluck("symbol")).to contain_exactly("AAPL", "MSFT", "NVDA")
  end

  it "allows a corrected request to reuse a key rolled back by validation" do
    post "/v1/reports", params: { symbol: "bad symbol" }, headers: write_headers
    expect(response).to have_http_status(:unprocessable_content)

    post "/v1/reports", params: { symbol: "AAPL" }, headers: write_headers
    expect(response).to have_http_status(:accepted)
    expect(Report.pluck(:symbol)).to eq([ "AAPL" ])
    expect(IdempotencyRecord.count).to eq(1)
  end

  it "treats an expired idempotency record as a new request" do
    post "/v1/reports", params: { symbol: "AAPL" }, headers: write_headers
    IdempotencyRecord.find_by!(key: key).update!(expires_at: 1.minute.ago)

    post "/v1/reports", params: { symbol: "MSFT" }, headers: write_headers

    expect(response).to have_http_status(:accepted)
    expect(Report.pluck(:symbol)).to contain_exactly("AAPL", "MSFT")
    expect(response.headers["Idempotency-Replayed"]).to be_nil
  end

  it "rejects invalid report filters without querying provider work" do
    get "/v1/reports?status=unknown", headers: auth

    expect(response).to have_http_status(:bad_request)
    expect(JSON.parse(response.body)).to include("code" => "bad_request")
  end
end
