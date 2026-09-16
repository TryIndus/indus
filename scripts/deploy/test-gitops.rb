require "yaml"

# Check the rendered manifest, including defaults and environment overrides.
environment = ARGV.fetch(0)
branch = {"staging" => "staging", "production" => "main"}.fetch(environment)
documents = YAML.load_stream($stdin.read).compact
applications = documents.select { |document| document["kind"] == "Application" }
raise "No applications rendered" if applications.empty?

sources = applications.flat_map do |application|
  spec = application.fetch("spec")
  spec.fetch("sources", [spec["source"]]).compact
end.select { |source| source["repoURL"] == "https://github.com/TryIndus/indus.git" }
raise "No repository sources rendered" if sources.empty?
sources.each do |source|
  raise "#{environment} reconciles the wrong branch" unless source["targetRevision"] == branch
end

project = documents.find { |document| document["kind"] == "AppProject" }
allowed = project.fetch("spec").fetch("clusterResourceWhitelist").map { |rule| rule.fetch("kind") }
%w[MutatingWebhookConfiguration ValidatingWebhookConfiguration CSIDriver APIService].each do |kind|
  raise "Required addon kind #{kind} blocked by AppProject" unless allowed.include?(kind)
end

provider = applications.find { |app| app.dig("metadata", "name") == "secrets-store-csi-provider-aws" }
unless provider.dig("spec", "source", "helm", "valuesObject", "secrets-store-csi-driver", "install") == false
  raise "The AWS provider must not install a second CSI driver"
end
puts "Passed #{environment} rendered GitOps regression checks."
