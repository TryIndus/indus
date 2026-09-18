require "rails_helper"

RSpec.describe Authentication::CognitoVerifier do
  let(:key) { OpenSSL::PKey::RSA.generate(2048) }
  let(:issuer) { "https://cognito-idp.us-east-1.amazonaws.com/test-pool" }
  let(:client_id) { "public-web-client" }
  let(:jwks_loader) { ->(_url) { { keys: [ JWT::JWK.new(key.public_key, kid: "primary").export ] } } }
  let(:profile) { { "sub" => "cognito-user", "email" => "user@example.test", "email_verified" => true } }
  let(:userinfo_loader) { ->(_url, _token) { profile } }
  subject(:verifier) do
    described_class.new(issuer: issuer, audience: nil, algorithms: [ "RS256" ],
      jwks_url: "#{issuer}/.well-known/jwks.json", jwks_loader: jwks_loader,
      client_id: client_id, userinfo_url: "https://indus.auth.us-east-1.amazoncognito.com/oauth2/userInfo",
      userinfo_loader: userinfo_loader)
  end

  def token(claims = {})
    payload = { iss: issuer, sub: "cognito-user", token_use: "access", client_id: client_id,
      exp: 5.minutes.from_now.to_i }.merge(claims)
    JWT.encode(payload, key, "RS256", kid: "primary")
  end

  it "accepts a Cognito access token and adds verified profile claims" do
    expect(verifier.verify(token)).to include("sub" => "cognito-user", "email" => "user@example.test")
  end

  it "rejects an ID token at the API boundary" do
    expect { verifier.verify(token(token_use: "id")) }.to raise_error(Authentication::Unauthorized, /access token/)
  end

  it "rejects an access token issued to another client" do
    expect { verifier.verify(token(client_id: "another-client")) }.to raise_error(Authentication::Unauthorized, /client/)
  end

  it "rejects an unverified email from the user-info endpoint" do
    profile["email_verified"] = false
    expect { verifier.verify(token) }.to raise_error(Authentication::Unauthorized, /verified email/)
  end

  it "rejects mismatched user-info subjects" do
    profile["sub"] = "another-user"
    expect { verifier.verify(token) }.to raise_error(Authentication::Unauthorized, /subject/)
  end
end
