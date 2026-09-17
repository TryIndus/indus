require "yaml"
require "open3"

workflow = YAML.load_file(File.expand_path("../../.github/workflows/deploy-application.yml", __dir__))
job = workflow.fetch("jobs").fetch("deploy")
steps = job.fetch("steps")
pr = steps.find { |step| step["id"] == "deployment-pr" }
raise "Deployment PR must use the built-in token" unless pr.fetch("with").fetch("token") == '${{ github.token }}'
%w[contents pull-requests actions].each do |permission|
  raise "Missing #{permission} permission" unless job.fetch("permissions")[permission] == "write"
end
dispatch = steps.find { |step| step["name"] == "Dispatch verification for the deployment PR" }
raise "Dispatch must require an open PR" unless dispatch.fetch("if") == "steps.deployment-pr.outputs.pull-request-number != ''"
shell = dispatch.fetch("run")

%w[main staging].each do |branch|
  head = "deploy/application-#{branch}-testsha"
  stdout, stderr, status = Open3.capture3(
    {"DEPLOYMENT_BRANCH" => head}, "bash", "-c",
    "gh() { printf '%s\\n' \"$*\"; }\n" + shell
  )
  raise stderr unless status.success?
  expected = %w[verification.yml aws-foundation.yml].map { |name| "workflow run #{name} --ref #{head}" }
  raise "Checks must target the deployment PR head branch" unless stdout.lines.map(&:strip) == expected
end

_, _, status = Open3.capture3(
  {"DEPLOYMENT_BRANCH" => "deploy/application-main-testsha"}, "bash", "-c",
  "gh() { return 1; }\n" + shell
)
raise "Failed verification dispatch must fail the deployment" if status.success?

digest_update = steps.find { |step| step["name"] == "Update the branch GitOps digest" }.fetch("run")
unless digest_update.include?("IMAGE_DIGEST") && digest_update.include?("/^imageDigest: /") && digest_update.include?("grep -Fqx")
  raise "Deployment must update only the tracked immutable image digest"
end
puts "Passed built-in token and deployment verification dispatch checks."
