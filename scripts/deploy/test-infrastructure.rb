require "yaml"
require "open3"

verification_template = File.read(File.expand_path("../../infra/terraform/modules/environment/templates/cognito-verification.html", __dir__))
raise "Cognito verification template must include Cognito's code placeholder" unless verification_template.include?("{####}")
raise "Cognito verification template must return users to Indus" unless verification_template.include?("${app_url}")
raise "Cognito verification template must cover password recovery" unless verification_template.include?("Forgot password?")
raise "Cognito verification template must not expose Cognito branding" if verification_template.match?(/cognito/i)

identity = File.read(File.expand_path("../../infra/terraform/modules/environment/identity.tf", __dir__))
raise "Branded email must remain opt-in" unless identity.include?("for_each = var.enable_branded_cognito_email ? [1] : []")
raise "Branded email must use Cognito's code confirmation flow" unless identity.include?("default_email_option = \"CONFIRM_WITH_CODE\"")
raise "Branded email must use the verified SES sender" unless identity.include?("email_sending_account = \"DEVELOPER\"")

# Exercise the workflow's actual shell without AWS credentials or Terraform writes.
workflow = YAML.load_file(File.expand_path("../../.github/workflows/deploy-infrastructure.yml", __dir__))
target = workflow.fetch("jobs").fetch("target").fetch("steps").first.fetch("run")
cases = [
  ["main", "plan", "", true],
  ["main", "apply", "", true],
  ["main", "plan-destroy-production", "destroy-production", true],
  ["main", "destroy-production", "destroy-production", true],
  ["main", "plan-destroy-production", "", false],
  ["main", "destroy-production", "", false],
  ["staging", "plan", "", false],
  ["staging", "apply", "", false],
  ["feature/test", "apply", "", false],
  ["main", "unexpected", "", false],
  ["main", "apply", "$(printf INJECTION >&2)", true],
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
plan = plan.gsub('${{ needs.target.outputs.environment }}', "production")
plan = "terraform() { printf '%s\\n' \"$*\"; }\n" + plan

%w[apply plan-destroy-production destroy-production].each do |operation|
  stdout, stderr, status = Open3.capture3({"OPERATION" => operation}, "bash", "-c", plan)
  raise stderr unless status.success?
  commands = stdout.lines
  raise "Terraform init was not called" unless commands.first.include?(" init ")
  case operation
  when "apply"
    raise "Expected complete restore plan" if commands.last.include?("-destroy") || commands.last.include?("-target")
  when "plan-destroy-production", "destroy-production"
    raise "Expected complete destroy plan" unless commands.last.include?("plan -destroy") && !commands.last.include?("-target")
  end
end

puts "Passed infrastructure branch, confirmation, and lifecycle regression checks."
