# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "open3"
require "tempfile"

class PutSecretTest < Minitest::Test
  SCRIPT = File.expand_path("../aws/put-secret.sh", __dir__)

  VALID_PAYLOADS = {
    "database-platform" => { "username" => "indus_platform", "password" => "platform-password" },
    "database-market" => { "username" => "indus_market_writer", "password" => "market-password" },
    "database-migration" => {
      "username" => "indus_migrator",
      "password" => "migration-password",
      "DATABASE_URL" => "postgresql://indus_migrator:password@proxy.example/indus"
    },
    "platform-api" => { "DATABASE_URL" => "postgresql://platform.example/indus" },
    "market-data" => { "DATABASE_URL" => "postgresql://market.example/indus" },
    "research-worker" => { "DATABASE_URL" => "postgresql://platform.example/indus" }
  }.freeze

  def test_every_supported_secret_has_a_non_mutating_dry_run
    VALID_PAYLOADS.each do |workload, payload|
      stdout, stderr, status = run_secret(workload: workload, payload: payload)

      assert status.success?, "#{workload}: #{stderr}"
      assert_includes stdout, "indus-development/#{workload}"
      assert_includes stdout, "No secret value was read by AWS"
      payload.each_value { |value| refute_includes stdout, value }
    end
  end

  def test_database_secrets_require_the_exact_runtime_identity
    {
      "database-platform" => "indus_market_writer",
      "database-market" => "indus_platform",
      "database-migration" => "indus_platform_owner"
    }.each do |workload, wrong_username|
      payload = VALID_PAYLOADS.fetch(workload).merge("username" => wrong_username)
      _stdout, _stderr, status = run_secret(workload: workload, payload: payload)

      refute status.success?, "accepted #{wrong_username} for #{workload}"
    end
  end

  def test_migration_secret_requires_a_database_url
    payload = VALID_PAYLOADS.fetch("database-migration").reject { |key, _value| key == "DATABASE_URL" }
    _stdout, _stderr, status = run_secret(workload: "database-migration", payload: payload)

    refute status.success?
  end

  def test_empty_or_non_string_secret_values_are_rejected
    [
      { "DATABASE_URL" => "" },
      { "DATABASE_URL" => 123 },
      { "DATABASE_URL" => nil },
      []
    ].each do |payload|
      _stdout, _stderr, status = run_secret(workload: "platform-api", payload: payload)

      refute status.success?, "accepted #{payload.inspect}"
    end
  end

  def test_group_or_world_readable_secret_file_is_rejected
    stdout, stderr, status = run_secret(
      workload: "platform-api",
      payload: VALID_PAYLOADS.fetch("platform-api"),
      permissions: 0o644
    )

    assert_equal 2, status.exitstatus
    assert_empty stdout
    assert_includes stderr, "chmod 600"
  end

  def test_unknown_environment_and_workload_are_rejected
    [
      [ "preview", "platform-api" ],
      [ "development", "unknown-service" ]
    ].each do |environment, workload|
      _stdout, stderr, status = run_secret(
        environment: environment,
        workload: workload,
        payload: VALID_PAYLOADS.fetch("platform-api")
      )

      assert_equal 2, status.exitstatus
      assert_includes stderr, "Usage:"
    end
  end

  private

  def run_secret(workload:, payload:, environment: "development", permissions: 0o600)
    Tempfile.create([ "indus secret ", ".json" ]) do |file|
      file.write(JSON.generate(payload))
      file.flush
      file.chmod(permissions)
      return Open3.capture3(SCRIPT, environment, workload, file.path)
    end
  end
end
