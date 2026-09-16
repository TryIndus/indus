require "yaml"
require "open3"

# Exercise the workflow's actual shell without AWS credentials or Terraform writes.
workflow = YAML.load_file(File.expand_path("../../.github/workflows/deploy-infrastructure.yml", __dir__))
target = workflow.fetch("jobs").fetch("target").fetch("steps").first.fetch("run")
cases = [
  ["staging", "tear-down", "tear-down-staging", true],
  ["staging", "tear-up", "", true],
  ["staging", "destroy", "destroy-staging", true],
  ["main", "apply", "", true],
  ["main", "tear-down", "tear-down-staging", false],
  ["main", "tear-up", "", false],
  ["main", "destroy", "destroy-staging", false],
  ["feature/test", "apply", "", false],
  ["staging", "unexpected", "", false],
  ["staging", "tear-down", "$(printf INJECTION >&2)", false],
]

cases.each do |branch, operation, confirmation, expected|
  _, stderr, status = Open3.capture3(
    {"GITHUB_REF_NAME" => branch, "OPERATION" => operation,
     "CONFIRMATION" => confirmation, "GITHUB_OUTPUT" => File::NULL},
    "bash", "-c", target
  )
  raise "Unexpected result for #{branch}/#{operation}: #{stderr}" unless status.success? == expected
  raise "Confirmation was evaluated as shell code" if stderr.include?("INJECTION")
end

plan = workflow.fetch("jobs").fetch("terraform").fetch("steps")
  .find { |step| step["name"] == "Plan" }.fetch("run")
plan = plan.gsub('${{ needs.target.outputs.environment }}', "staging")
plan = "terraform() { printf '%s\\n' \"$*\"; }\n" + plan

%w[tear-down tear-up destroy].each do |operation|
  stdout, stderr, status = Open3.capture3({"OPERATION" => operation}, "bash", "-c", plan)
  raise stderr unless status.success?
  commands = stdout.lines
  raise "Terraform init was not called" unless commands.first.include?(" init ")
  case operation
  when "tear-down"
    raise "Expected targeted destroy" unless commands.last.include?("plan -destroy")
    %w[aws_rds_cluster_instance.data aws_db_proxy.data aws_eks_cluster.this aws_nat_gateway.primary].each do |resource|
      raise "Runtime resource was retained: #{resource}" unless commands.last.include?("-target=module.environment.#{resource}")
    end
    %w[aws_rds_cluster.data aws_backup_selection.primary aws_s3_bucket.data aws_cognito_user_pool.this aws_kms_key.data].each do |resource|
      raise "Durable resource targeted: #{resource}" if commands.last.include?("-target=module.environment.#{resource}")
    end
  when "tear-up"
    raise "Expected complete restore plan" if commands.last.include?("-destroy") || commands.last.include?("-target")
  when "destroy"
    raise "Expected complete destroy plan" unless commands.last.include?("plan -destroy") && !commands.last.include?("-target")
  end
end

puts "Passed infrastructure branch, confirmation, and lifecycle regression checks."
