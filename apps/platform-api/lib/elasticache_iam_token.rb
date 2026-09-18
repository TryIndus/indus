require "aws-sdk-core"
require "aws-sigv4"
require "uri"

class ElasticacheIamToken
  def initialize(cache_name:, user_id:, region:, credentials_provider: Aws::CredentialProviderChain.new.resolve)
    @cache_name = cache_name.downcase
    @user_id = user_id
    @signer = Aws::Sigv4::Signer.new(
      service: "elasticache",
      region: region,
      credentials_provider: credentials_provider
    )
  end

  def call(_username = nil)
    query = URI.encode_www_form(Action: "connect", User: @user_id, ResourceType: "ServerlessCache")
    @signer.presign_url(http_method: "GET", url: "http://#{@cache_name}/?#{query}", expires_in: 900)
      .to_s.delete_prefix("http://")
  end
end
