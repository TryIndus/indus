require "rails_helper"

RSpec.describe Authentication::CognitoUserLoader do
  let(:response) do
    Net::HTTPOK.new("1.1", "200", "OK").tap do |value|
      allow(value).to receive(:body).and_return({
        UserAttributes: [
          { Name: "sub", Value: "cognito-user" },
          { Name: "email", Value: "user@example.test" },
          { Name: "email_verified", Value: "true" },
          { Name: "name", Value: "Avery Investor" }
        ]
      }.to_json)
    end
  end
  let(:http) { instance_double(Net::HTTP, request: response) }

  before do
    allow(Net::HTTP).to receive(:start).and_yield(http)
  end

  it "loads and caches verified Cognito attributes without retaining the raw token" do
    loader = described_class.new
    2.times do
      expect(loader.call("https://cognito-idp.us-east-1.amazonaws.com", "secret-token"))
        .to include("sub" => "cognito-user", "email" => "user@example.test", "email_verified" => true)
    end

    expect(Net::HTTP).to have_received(:start).once
    expect(http).to have_received(:request).with(satisfy do |request|
      request["X-Amz-Target"] == "AWSCognitoIdentityProviderService.GetUser" &&
        JSON.parse(request.body) == { "AccessToken" => "secret-token" }
    end)
    expect(loader.instance_variable_get(:@cache).keys).to all(match(/\A[0-9a-f]{64}\z/))
    expect(loader.instance_variable_get(:@cache).keys).not_to include("secret-token")
  end

  it "rejects a non-HTTPS endpoint before sending the access token" do
    loader = described_class.new

    expect { loader.call("http://cognito-idp.us-east-1.amazonaws.com", "secret-token") }
      .to raise_error(Authentication::CognitoUserLoader::FetchError, /HTTPS/)
    expect(Net::HTTP).not_to have_received(:start)
  end
end
