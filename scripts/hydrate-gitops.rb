#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "yaml"

environment, output_file, mode = ARGV
abort "Usage: #{$PROGRAM_NAME} ENVIRONMENT TERRAFORM_OUTPUT_JSON [--write]" unless %w[development staging production].include?(environment) && output_file

outputs = JSON.parse(File.read(output_file))
outputs = outputs.fetch("value") if outputs.key?("value")
forbidden_keys = outputs.keys.grep(/password|token|credential|secret_value/i)
abort "refusing Terraform output containing secret-shaped keys" unless forbidden_keys.empty?

root = File.expand_path("..", __dir__)
workload_path = File.join(root, "infra", "gitops", "environments", environment, "values.yaml")
control_path = File.join(root, "infra", "helm", "indus-applications", "values-#{environment}.yaml")
workload = YAML.safe_load(File.read(workload_path), permitted_classes: [], permitted_symbols: [], aliases: false)
control = YAML.safe_load(File.read(control_path), permitted_classes: [], permitted_symbols: [], aliases: false)

cluster = outputs.fetch("cluster")
edge = outputs.fetch("edge")
identity = outputs.fetch("identity")
data = outputs.fetch("data_endpoints")
roles = outputs.fetch("workload_role_arns")
secrets = outputs.fetch("secret_arns")
observability = outputs.fetch("observability")

workload["aws"].merge!(
  "webBucket" => data.fetch("web_bucket"),
  "cloudfrontDistributionId" => edge.fetch("cloudfront_distribution_id"),
  "targetGroups" => {
    "platformApi" => edge.fetch("api_target_group_arn"),
    "marketData" => edge.fetch("stream_target_group_arn")
  }
)
workload["identity"] = { "issuer" => identity.fetch("issuer"), "audience" => identity.fetch("client_id") }
workload["roles"] = {
  "platformApi" => roles.fetch("platform_api"),
  "sidekiq" => roles.fetch("sidekiq"),
  "platformOutbox" => roles.fetch("platform_outbox"),
  "reportsConsumer" => roles.fetch("reports_consumer"),
  "marketData" => roles.fetch("market_data"),
  "researchWorker" => roles.fetch("research_worker"),
  "webPublisher" => roles.fetch("web_publisher")
}
workload["secrets"] = {
  "platformApi" => secrets.fetch("platform_api"),
  "marketData" => secrets.fetch("market_data"),
  "researchWorker" => secrets.fetch("research_worker")
}
workload["config"].merge!(
  "rdsProxyEndpoint" => data.fetch("rds_proxy"),
  "redisEndpoint" => data.fetch("redis"),
  "mskBootstrapBrokers" => data.fetch("msk_bootstrap_brokers"),
  "artifactBucket" => data.fetch("artifact_bucket"),
  "rawEventsBucket" => data.fetch("raw_events_bucket")
)

control.merge!(
  "clusterName" => cluster.fetch("name"),
  "vpcId" => cluster.fetch("vpc_id"),
  "prometheusRemoteWriteUrl" => observability.fetch("prometheus_remote_write_url")
)
control["roles"] = {
  "loadBalancer" => roles.fetch("load_balancer"),
  "otelCollector" => roles.fetch("otel_collector")
}

rendered = { workload_path => YAML.dump(workload, line_width: -1), control_path => YAML.dump(control, line_width: -1) }
if mode == "--write"
  rendered.each { |path, contents| File.write(path, contents) }
  warn "Updated non-secret GitOps values for #{environment}. Review every diff before commit."
else
  puts "# Dry run only. Re-run with --write after reviewing these generated documents."
  rendered.each do |path, contents|
    puts "--- # #{path.delete_prefix("#{root}/")}"
    puts contents
  end
end
