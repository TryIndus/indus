#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

for command in terraform helm ruby jq rg shellcheck; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Missing required validator: $command" >&2
    exit 1
  fi
done

export TF_IN_AUTOMATION=true
terraform fmt -check -recursive infra/terraform

terraform_roots=(
  infra/terraform/bootstrap/shared
  infra/terraform/environments/development
  infra/terraform/environments/staging
  infra/terraform/environments/production
)
for terraform_root in "${terraform_roots[@]}"; do
  terraform -chdir="$terraform_root" init -backend=false -input=false -lockfile=readonly >/dev/null
  terraform -chdir="$terraform_root" validate
done

helm lint infra/helm/indus-platform
helm lint infra/helm/indus-applications

render_dir="$(mktemp -d "${TMPDIR:-/tmp}/indus-phase4-render.XXXXXX")"
trap 'rm -rf "$render_dir"' EXIT
for environment in development staging production; do
  helm template indus infra/helm/indus-platform \
    --namespace indus \
    --values "infra/gitops/environments/$environment/values.yaml" \
    >"$render_dir/platform-$environment.yaml"
  helm template indus-applications infra/helm/indus-applications \
    --namespace argocd \
    --values "infra/helm/indus-applications/values-$environment.yaml" \
    >"$render_dir/applications-$environment.yaml"
done

ruby -e '
  require "yaml"
  ARGV.each do |file|
    count = 0
    YAML.load_stream(File.read(file)) { |document| count += 1 if document }
    abort "#{file} rendered no resources" if count.zero?
  end
' "$render_dir"/*.yaml

ruby -e '
  require "yaml"
  ARGV.each do |file|
    documents = YAML.load_stream(File.read(file)).compact
    %w[platform-api sidekiq].each do |name|
      deployment = documents.find { |doc| doc["kind"] == "Deployment" && doc.dig("metadata", "name") == name }
      abort "#{file} is missing #{name}" unless deployment
      env = deployment.dig("spec", "template", "spec", "containers", 0, "env").to_h { |item| [item["name"], item["value"]] }
      required = %w[REDIS_AUTH_MODE REDIS_ENDPOINT REDIS_PORT REDIS_IAM_CACHE_NAME REDIS_IAM_USER]
      abort "#{file} has incomplete Redis IAM configuration for #{name}" unless (required - env.keys).empty?
      abort "#{file} does not enable Redis IAM for #{name}" unless env["REDIS_AUTH_MODE"] == "iam"
    end
    projected = documents.select { |doc| doc["kind"] == "SecretProviderClass" }
      .flat_map { |doc| doc.dig("spec", "secretObjects", 0, "data") || [] }
    abort "#{file} still projects REDIS_URL" if projected.any? { |item| item["key"] == "REDIS_URL" }

    jobs = documents.select { |document| document["kind"] == "Job" }
    migrations = jobs.select { |job| job.dig("metadata", "name")&.include?("database-migrate") }
    abort "#{file} must render separate platform and market migration jobs" unless migrations.length == 2
    migrations.each do |job|
      spec = job.dig("spec", "template", "spec")
      abort "#{file} migration job bypasses the migration service account" unless spec["serviceAccountName"] == "database-migrator"
      container = spec.fetch("containers").first
      role_option = container.fetch("env").find { |entry| entry["name"] == "PGOPTIONS" }&.fetch("value", nil)
      expected = [
        "-c role=indus_platform_owner -c search_path=public,pg_catalog",
        "-c role=indus_market_owner -c search_path=market_data,pg_catalog"
      ]
      abort "#{file} migration job has no explicit owner role and schema" unless expected.include?(role_option)
    end
  end
' "$render_dir"/platform-*.yaml

for required_role in indus_platform indus_market_writer indus_migrator indus_platform_owner indus_market_owner; do
  rg -q "${required_role}" scripts/aws/database-roles.sql
done
rg -q 'database_platform' infra/terraform/modules/environment/data.tf infra/terraform/modules/environment/locals.tf
rg -q 'database_market' infra/terraform/modules/environment/data.tf infra/terraform/modules/environment/locals.tf
rg -q 'database_migration' infra/terraform/modules/environment/data.tf infra/terraform/modules/environment/locals.tf
ruby -e '
  require "yaml"
  Dir["infra/gitops/**/*.{yaml,yml}"].each do |file|
    YAML.load_stream(File.read(file)) { |_document| }
  end
'

jq -e . infra/helm/indus-platform/values.schema.json >/dev/null
shellcheck infra/images/web-publisher/publish.sh scripts/evaluate-cutover.sh scripts/validate-phase4.sh scripts/aws/*.sh
ruby -c scripts/hydrate-gitops.rb >/dev/null
ruby scripts/test/hydrate_gitops_test.rb
ruby -c scripts/update-gitops-images.rb >/dev/null
if command -v actionlint >/dev/null 2>&1; then
  actionlint .github/workflows/*.yml
fi

if git ls-files | rg -q '(^|/)(terraform\.tfstate|terraform\.tfvars|backend\.hcl|secrets\.auto\.tfvars|\.env)$'; then
  echo "A local state, variable, backend, or environment file is tracked." >&2
  exit 1
fi

if rg -n 'AKIA[0-9A-Z]{16}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----' \
  --glob '!*.lock' --glob '!scripts/validate-phase4.sh' .; then
  echo "A credential-shaped value is present in tracked source." >&2
  exit 1
fi

git diff --check
echo "Phase 4 offline validation passed."
