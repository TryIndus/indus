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
  Dir["infra/gitops/**/*.{yaml,yml}"].each do |file|
    YAML.load_stream(File.read(file)) { |_document| }
  end
'

jq -e . infra/helm/indus-platform/values.schema.json >/dev/null
shellcheck infra/images/web-publisher/publish.sh scripts/evaluate-cutover.sh scripts/validate-phase4.sh scripts/aws/*.sh
ruby -c scripts/hydrate-gitops.rb >/dev/null
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
