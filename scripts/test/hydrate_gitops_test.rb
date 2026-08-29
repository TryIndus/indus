# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "open3"
require "tempfile"

class HydrateGitopsTest < Minitest::Test
  def test_hydrates_structured_redis_connection_identity
    output = terraform_output

    Tempfile.create([ "terraform-output", ".json" ]) do |file|
      file.write(JSON.generate(output))
      file.flush
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        File.expand_path("../hydrate-gitops.rb", __dir__),
        "development",
        file.path
      )

      assert status.success?, stderr
      assert_includes stdout, "redisEndpoint: cache.example"
      assert_includes stdout, "redisPort: 6380"
      assert_includes stdout, "redisCacheName: indus-development"
      assert_includes stdout, "redisUser: indus-development-app"
      assert_includes stdout, "databaseMigrator: arn:aws:iam::111111111111:role/database-migrator"
      assert_includes stdout, "databaseMigration: arn:aws:secretsmanager:ca-central-1:111111111111:secret:database-migration"
    end
  end

  private

  def terraform_output
    {
      "cluster" => { "name" => "indus-development", "vpc_id" => "vpc-example" },
      "edge" => {
        "cloudfront_distribution_id" => "distribution-example",
        "api_target_group_arn" => "arn:aws:elasticloadbalancing:ca-central-1:111111111111:targetgroup/api/example",
        "stream_target_group_arn" => "arn:aws:elasticloadbalancing:ca-central-1:111111111111:targetgroup/stream/example"
      },
      "identity" => { "issuer" => "https://issuer.example", "client_id" => "client-example" },
      "data_endpoints" => {
        "rds_proxy" => "database.example",
        "redis" => {
          "endpoint" => "cache.example",
          "port" => 6380,
          "cache_name" => "indus-development",
          "user_name" => "indus-development-app"
        },
        "msk_bootstrap_brokers" => "broker.example:9098",
        "artifact_bucket" => "artifact-example",
        "raw_events_bucket" => "raw-example",
        "web_bucket" => "web-example"
      },
      "workload_role_arns" => role_arns,
      "secret_arns" => {
        "platform_api" => "arn:aws:secretsmanager:ca-central-1:111111111111:secret:platform-api",
        "market_data" => "arn:aws:secretsmanager:ca-central-1:111111111111:secret:market-data",
        "research_worker" => "arn:aws:secretsmanager:ca-central-1:111111111111:secret:research-worker",
        "database_migration" => "arn:aws:secretsmanager:ca-central-1:111111111111:secret:database-migration"
      },
      "observability" => { "prometheus_remote_write_url" => "https://aps.example/api/v1/remote_write" }
    }
  end

  def role_arns
    %w[
      database_migrator load_balancer market_data otel_collector platform_api platform_outbox
      reports_consumer research_worker sidekiq web_publisher
    ].to_h do |name|
      [ name, "arn:aws:iam::111111111111:role/#{name.tr("_", "-")}" ]
    end
  end
end
