require "rails_helper"

RSpec.describe "domain constraints" do
  let(:user) { User.create!(issuer: "issuer", external_subject: SecureRandom.uuid, email: "domain@example.test", display_name: "Domain") }

  it "prevents duplicate tenant favorites" do
    user.favorites.create!(symbol: "AAPL")
    expect { user.favorites.create!(symbol: "aapl") }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it "requires a positive position quantity" do
    portfolio = user.portfolios.create!(name: "Long term")
    expect { portfolio.positions.create!(symbol: "AAPL", quantity: 0, average_cost: 1) }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it "restricts reports to durable workflow states" do
    expect { user.reports.create!(symbol: "AAPL", status: "mystery") }.to raise_error(ActiveRecord::RecordInvalid)
  end
end
