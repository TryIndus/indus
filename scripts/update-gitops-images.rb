#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"

environment = ARGV.fetch(0)
environments = %w[development staging production]
abort "unsupported environment" unless environments.include?(environment)

release_id = ENV.fetch("RELEASE_ID")
abort "RELEASE_ID must be a full lowercase Git SHA" unless release_id.match?(/\A[0-9a-f]{40}\z/)

images = {
  "platformApi" => ENV.fetch("PLATFORM_API_IMAGE"),
  "marketData" => ENV.fetch("MARKET_DATA_IMAGE"),
  "researchWorker" => ENV.fetch("PLATFORM_API_IMAGE"),
  "web" => ENV.fetch("WEB_IMAGE")
}
images.each_value do |image|
  abort "image must include an immutable sha256 digest" unless image.match?(/@sha256:[0-9a-f]{64}\z/)
end
expected_repositories = {
  "platformApi" => "/indus/platform-api@sha256:",
  "marketData" => "/indus/market-data@sha256:",
  "researchWorker" => "/indus/platform-api@sha256:",
  "web" => "/indus/web@sha256:"
}
images.each do |name, image|
  abort "#{name} image belongs to an unexpected repository" unless image.include?(expected_repositories.fetch(name))
end

target_path = File.join(__dir__, "..", "infra", "gitops", "environments", environment, "values.yaml")
target = YAML.safe_load(File.read(target_path), permitted_classes: [], permitted_symbols: [], aliases: false)

previous_environment = { "staging" => "development", "production" => "staging" }[environment]
if previous_environment
  previous_path = File.join(__dir__, "..", "infra", "gitops", "environments", previous_environment, "values.yaml")
  previous = YAML.safe_load(File.read(previous_path), permitted_classes: [], permitted_symbols: [], aliases: false)
  abort "the exact image set must be promoted through #{previous_environment} first" unless images == previous.fetch("images")
  abort "the exact release must be promoted through #{previous_environment} first" unless release_id == previous.dig("webPublisher", "releaseId")
end

target["images"] = images
target["webPublisher"] ||= {}
target["webPublisher"]["releaseId"] = release_id
File.write(target_path, YAML.dump(target, line_width: -1))
