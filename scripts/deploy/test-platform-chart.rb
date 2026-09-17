#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"

documents = $stdin.read.split(/^---\s*$/).map do |document|
  YAML.safe_load(document, permitted_classes: [], permitted_symbols: [], aliases: true)
end.compact
abort "rendered platform chart is empty" if documents.empty?

failures = []
workloads = documents.select { |document| %w[Deployment Job].include?(document["kind"]) }

expected_workloads = %w[
  platform-api market-data sidekiq platform-outbox reports-consumer research-worker
]
rendered_names = workloads.map { |document| document.dig("metadata", "name").to_s }
expected_workloads.each do |name|
  failures << "missing workload #{name}" unless rendered_names.include?(name)
end

workloads.each do |workload|
  name = workload.dig("metadata", "name")
  pod_spec = workload.dig("spec", "template", "spec") || {}
  pod_security = pod_spec.fetch("securityContext", {})
  failures << "#{name} must run as non-root" unless pod_security["runAsNonRoot"] == true
  failures << "#{name} must use RuntimeDefault seccomp" unless pod_security.dig("seccompProfile", "type") == "RuntimeDefault"
  failures << "#{name} must use a service account" if pod_spec["serviceAccountName"].to_s.empty?

  pod_spec.fetch("containers", []).each do |container|
    container_name = "#{name}/#{container['name']}"
    security = container.fetch("securityContext", {})
    failures << "#{container_name} allows privilege escalation" unless security["allowPrivilegeEscalation"] == false
    failures << "#{container_name} has a writable root filesystem" unless security["readOnlyRootFilesystem"] == true
    failures << "#{container_name} does not drop all capabilities" unless security.dig("capabilities", "drop")&.include?("ALL")
    failures << "#{container_name} image is not digest-pinned" unless container["image"].to_s.match?(/@sha256:[0-9a-f]{64}\z/)

    resources = container.fetch("resources", {})
    failures << "#{container_name} lacks resource requests" if resources.fetch("requests", {}).empty?
    failures << "#{container_name} lacks resource limits" if resources.fetch("limits", {}).empty?
  end
end

documents.select { |document| document["kind"] == "Service" }.each do |service|
  failures << "#{service.dig('metadata', 'name')} may not create a load balancer" if service.dig("spec", "type") == "LoadBalancer"
end

network_policies = documents.select { |document| document["kind"] == "NetworkPolicy" }
failures << "default-deny network policy is missing" unless network_policies.any? do |policy|
  policy.dig("metadata", "name") == "default-deny" && policy.dig("spec", "podSelector") == {}
end

service_accounts = documents.count { |document| document["kind"] == "ServiceAccount" }
secret_providers = documents.count { |document| document["kind"] == "SecretProviderClass" }
failures << "expected 8 workload service accounts, rendered #{service_accounts}" unless service_accounts == 8
failures << "expected 4 secret provider classes, rendered #{secret_providers}" unless secret_providers == 4

abort failures.join("\n") unless failures.empty?

puts "validated #{workloads.length} workloads and #{documents.length} Kubernetes resources"
