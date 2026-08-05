# frozen_string_literal: true

require "aws-sdk-core"
require "aws-sigv4"
require "openssl"
require "uri"

module RedisRuntime
  class ConfigurationError < StandardError; end

  class IamTokenProvider
    TOKEN_TTL_SECONDS = 900

    def initialize(cache_name:, username:, region:, credentials_provider: nil, signer: nil, clock: Time)
      @cache_name = cache_name
      @username = username
      @clock = clock
      @signer = signer || build_signer(region, credentials_provider)
    end

    # redis-client evaluates password callables every time it authenticates a
    # new or re-established connection. Do not cache this short-lived token.
    def call(requested_username)
      unless requested_username == @username
        raise ConfigurationError, "Redis IAM username does not match the configured ElastiCache user"
      end

      request_url = URI::HTTP.build(
        host: @cache_name,
        path: "/",
        query: URI.encode_www_form(Action: "connect", ResourceType: "ServerlessCache", User: @username)
      )
      signed_url = @signer.presign_url(
        http_method: "GET",
        url: request_url.to_s,
        expires_in: TOKEN_TTL_SECONDS,
        time: @clock.now
      )
      signed_url.to_s.delete_prefix("http://").delete_prefix("https://")
    end

    private

    def build_signer(region, credentials_provider)
      provider = credentials_provider || Aws::CredentialProviderChain.new.resolve
      raise ConfigurationError, "AWS credentials are unavailable for Redis IAM authentication" unless provider

      Aws::Sigv4::Signer.new(service: "elasticache", region: region, credentials_provider: provider)
    end
  end

  module_function

  def connection_options(environment = ENV, credentials_provider: nil, signer: nil, clock: Time)
    case environment.fetch("REDIS_AUTH_MODE", "url")
    when "url"
      { url: environment.fetch("REDIS_URL", "redis://localhost:6379/0") }
    when "iam"
      iam_connection_options(environment, credentials_provider:, signer:, clock:)
    else
      raise ConfigurationError, "REDIS_AUTH_MODE must be url or iam"
    end
  end

  def iam_connection_options(environment, credentials_provider:, signer:, clock:)
    endpoint = required(environment, "REDIS_ENDPOINT")
    cache_name = required(environment, "REDIS_IAM_CACHE_NAME")
    username = required(environment, "REDIS_IAM_USER")
    region = required(environment, "AWS_REGION")
    port = Integer(environment.fetch("REDIS_PORT", "6379"), 10)

    validate_endpoint!(endpoint)
    raise ConfigurationError, "REDIS_PORT must be between 1 and 65535" unless (1..65_535).cover?(port)

    {
      url: "rediss://#{endpoint}:#{port}/0",
      username:,
      password: IamTokenProvider.new(cache_name:, username:, region:, credentials_provider:, signer:, clock:),
      ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_PEER },
      reconnect_attempts: [ 0, 0.25, 1 ]
    }
  rescue ArgumentError
    raise ConfigurationError, "REDIS_PORT must be an integer"
  end
  private_class_method :iam_connection_options

  def required(environment, key)
    value = environment[key]
    raise ConfigurationError, "#{key} is required for Redis IAM authentication" if value.nil? || value.empty?

    value
  end
  private_class_method :required

  def validate_endpoint!(endpoint)
    uri = URI.parse("rediss://#{endpoint}")
    return if uri.host == endpoint && uri.userinfo.nil? && uri.path.empty? && uri.query.nil? && uri.fragment.nil?

    raise ConfigurationError, "REDIS_ENDPOINT must be a hostname without a scheme, port, or credentials"
  rescue URI::InvalidURIError
    raise ConfigurationError, "REDIS_ENDPOINT must be a valid hostname"
  end
  private_class_method :validate_endpoint!
end
