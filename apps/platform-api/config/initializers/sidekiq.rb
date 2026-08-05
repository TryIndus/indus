require Rails.root.join("lib/redis_runtime")

redis_options = RedisRuntime.connection_options

# The password callable signs a fresh IAM token whenever redis-client opens or
# reconnects a socket. Both blocks must receive it because a Sidekiq server can
# also enqueue client jobs.
Sidekiq.configure_server { |config| config.redis = redis_options }
Sidekiq.configure_client { |config| config.redis = redis_options }
