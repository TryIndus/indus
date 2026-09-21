redis = if ENV["REDIS_AUTH_MODE"] == "iam"
  require Rails.root.join("lib/elasticache_iam_token")
  {
    url: "rediss://#{ENV.fetch('REDIS_ENDPOINT')}:#{ENV.fetch('REDIS_PORT', 6379)}/0",
    username: ENV.fetch("REDIS_IAM_USER"),
    password: ElasticacheIamToken.new(
      cache_name: ENV.fetch("REDIS_IAM_CACHE_NAME"),
      user_id: ENV.fetch("REDIS_IAM_USER"),
      region: ENV.fetch("AWS_REGION")
    )
  }
else
  { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }
end

Sidekiq.configure_server { |config| config.redis = redis }
Sidekiq.configure_client { |config| config.redis = redis }
