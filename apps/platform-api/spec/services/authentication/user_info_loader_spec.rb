require "rails_helper"

RSpec.describe Authentication::UserInfoLoader do
  let(:response) do
    Net::HTTPOK.new("1.1", "200", "OK").tap do |value|
      allow(value).to receive(:body).and_return(
        { sub: "cognito-user", email: "user@example.test", email_verified: true }.to_json)
    end
  end
  let(:http) { instance_double(Net::HTTP, request: response) }

  before do
    allow(Net::HTTP).to receive(:start).and_yield(http)
  end

  it "caches a verified profile without retaining the raw access token as a key" do
    loader = described_class.new
    2.times do
      expect(loader.call("https://indus.auth.us-east-1.amazoncognito.com/oauth2/userInfo", "secret-token"))
        .to include("sub" => "cognito-user")
    end

    expect(Net::HTTP).to have_received(:start).once
    expect(loader.instance_variable_get(:@cache).keys).to all(match(/\A[0-9a-f]{64}\z/))
    expect(loader.instance_variable_get(:@cache).keys).not_to include("secret-token")
  end

  it "rejects a non-HTTPS endpoint before sending the access token" do
    loader = described_class.new

    expect { loader.call("http://identity.example.test/userInfo", "secret-token") }
      .to raise_error(Authentication::UserInfoLoader::FetchError, /HTTPS/)
    expect(Net::HTTP).not_to have_received(:start)
  end
end
