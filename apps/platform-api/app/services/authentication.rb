require "net/http"
require "digest"

module Authentication
  class Unauthorized < StandardError; end
  class ConfigurationError < StandardError; end

  class << self
    attr_writer :verifier

    def verifier
      @verifier ||= CognitoVerifier.from_env
    end

    def reset!
      @verifier = nil
    end
  end

  class TokenVerifier
    CLOCK_SKEW = 30

    def initialize(issuer:, audience:, algorithms:, jwks_url: nil, verification_key: nil, jwks_loader: JwksLoader.new)
      @issuer = issuer
      @audience = audience
      @jwks_url = jwks_url
      @algorithms = algorithms
      @verification_key = verification_key
      @jwks_loader = jwks_loader
    end

    def verify(token)
      options = { algorithms: @algorithms, iss: @issuer, verify_iss: true, leeway: CLOCK_SKEW }
      options[:jwks] = @jwks_loader.call(@jwks_url) if @jwks_url
      options.merge!(aud: @audience, verify_aud: true) if @audience.present?
      JWT.decode(token, @verification_key, true, options).first.tap { |claims| validate_subject!(claims) }
    rescue JWT::DecodeError, KeyError, JwksLoader::FetchError => error
      raise Unauthorized, error.message
    end

    private

    def validate_subject!(claims)
      raise Unauthorized, "token subject is missing" if claims["sub"].blank?
    end
  end

  class JwksLoader
    class FetchError < StandardError; end

    def initialize(ttl: 300, clock: Time)
      @ttl = ttl
      @clock = clock
      @cache = {}
      @mutex = Mutex.new
    end

    def call(url)
      @mutex.synchronize do
        cached = @cache[url]
        return cached[:value] if cached && cached[:expires_at] > @clock.now

        @cache[url] = { value: fetch(url), expires_at: @clock.now + @ttl }
        @cache[url][:value]
      end
    end

    private

    def fetch(url)
      uri = URI(url)
      raise FetchError, "JWKS URL must use HTTPS" unless uri.is_a?(URI::HTTPS)

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 2, read_timeout: 3) do |http|
        http.get(uri.request_uri, { "Accept" => "application/json" })
      end
      raise FetchError, "JWKS endpoint returned #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    rescue JSON::ParserError, SocketError, SystemCallError, Timeout::Error, URI::InvalidURIError => error
      raise FetchError, "JWKS fetch failed: #{error.class}"
    end
  end

  class UserInfoLoader
    class FetchError < StandardError; end

    def initialize(ttl: 60, clock: Time)
      @ttl = ttl
      @clock = clock
      @cache = {}
      @mutex = Mutex.new
    end

    def call(url, token)
      cache_key = Digest::SHA256.hexdigest(token)
      @mutex.synchronize do
        cached = @cache[cache_key]
        return cached[:value] if cached && cached[:expires_at] > @clock.now

        @cache[cache_key] = { value: fetch(url, token), expires_at: @clock.now + @ttl }
        @cache[cache_key][:value]
      end
    end

    private

    def fetch(url, token)
      uri = URI(url)
      raise FetchError, "user-info URL must use HTTPS" unless uri.is_a?(URI::HTTPS)

      request = Net::HTTP::Get.new(uri.request_uri,
        { "Accept" => "application/json", "Authorization" => "Bearer #{token}" })
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 2, read_timeout: 3) do |http|
        http.request(request)
      end
      raise FetchError, "user-info endpoint rejected the token" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    rescue JSON::ParserError, SocketError, SystemCallError, Timeout::Error, URI::InvalidURIError => error
      raise FetchError, "user-info fetch failed: #{error.class}"
    end
  end

  class CognitoVerifier < TokenVerifier
    def initialize(client_id:, userinfo_url:, userinfo_loader: UserInfoLoader.new, **verifier_options)
      super(**verifier_options)
      @client_id = client_id
      @userinfo_url = userinfo_url
      @userinfo_loader = userinfo_loader
    end

    def self.from_env
      issuer = ENV.fetch("COGNITO_JWT_ISSUER")
      new(issuer: issuer, audience: nil, client_id: ENV.fetch("COGNITO_CLIENT_ID"),
        userinfo_url: ENV.fetch("COGNITO_USERINFO_URL"), jwks_url: "#{issuer}/.well-known/jwks.json",
        algorithms: [ "RS256" ])
    end

    def verify(token)
      claims = super
      raise Unauthorized, "token is not a Cognito access token" unless claims["token_use"] == "access"
      raise Unauthorized, "token client does not match" unless secure_match?(claims["client_id"], @client_id)

      profile = @userinfo_loader.call(@userinfo_url, token)
      raise Unauthorized, "user-info subject does not match" unless secure_match?(profile["sub"], claims["sub"])
      raise Unauthorized, "verified email is required" unless profile["email_verified"] == true

      claims.merge("email" => profile.fetch("email"), "name" => profile["name"])
    rescue KeyError, UserInfoLoader::FetchError => error
      raise Unauthorized, error.message
    end

    private

    def secure_match?(actual, expected)
      actual = actual.to_s
      expected = expected.to_s
      actual.bytesize == expected.bytesize && ActiveSupport::SecurityUtils.secure_compare(actual, expected)
    end
  end
end
