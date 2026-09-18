require "rails_helper"

RSpec.describe "authentication provider selection" do
  before { Authentication.reset! }

  after { Authentication.reset! }

  it "uses Cognito as the only identity provider" do
    allow(Authentication::CognitoVerifier).to receive(:from_env).and_return(:cognito)
    expect(Authentication.verifier).to eq(:cognito)
  end
end
