require "yaml"
require "json"
require "open3"

root = File.expand_path("../..", __dir__)
workflow = YAML.load_file(File.join(root, ".github/workflows/aws-foundation.yml"))
step = workflow.fetch("jobs").fetch("foundation").fetch("steps")
  .find { |item| item["name"] == "Test private GitOps bootstrap rendering" }
fixture = JSON.parse(step.fetch("run").match(/fixture='([^']+)'/)[1])

["staging", "production"].each do |environment|
  [nil, "aurora-test"].each do |endpoint|
    infrastructure = Marshal.load(Marshal.dump(fixture))
    if endpoint
      infrastructure["data_platform"]["database_endpoint"] = endpoint
      infrastructure["data_platform"]["rds_proxy_endpoint"] = nil
    end
    stdout, stderr, status = Open3.capture3(
      {"TERRAFORM_OUTPUT_JSON" => JSON.generate(infrastructure), "AWS_REGION" => "us-east-1"},
      File.join(root, "scripts/deploy/render-gitops-bootstrap.sh"), environment
    )
    raise stderr unless status.success?
    actual = JSON.parse(stdout).dig("spec", "source", "helm", "valuesObject", "platform", "values", "config", "rdsProxyEndpoint")
    raise "Incorrect database endpoint for #{environment}" unless actual == (endpoint || "database-test")
  end
end
puts "Passed proxy and direct database GitOps rendering for both environments."
