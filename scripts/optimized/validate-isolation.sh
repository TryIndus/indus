#!/usr/bin/env bash
set -euo pipefail

optimized=infra/optimized
[[ -d "$optimized" ]]

search() {
  local pattern="$1"
  local path="$2"
  if command -v rg >/dev/null; then
    rg -n --hidden --glob '!*.example' "$pattern" "$path"
  else
    grep -RInE --exclude='*.example' "$pattern" "$path"
  fi
}

! search 'terraform_remote_state|environments/production/terraform\.tfstate|indus-production|indus-staging' "$optimized"
! search 'aws_eks_|aws_rds_cluster|aws_db_proxy|aws_msk_|aws_elasticache_|aws_lb|aws_cloudfront_|aws_nat_gateway' "$optimized/terraform"
! git diff --name-only origin/main...HEAD | grep -E '^infra/terraform/'
grep -q 'optimized/production/terraform.tfstate' "$optimized/terraform/environment/backend.hcl.example"
grep -Eq 'Profile *= *"optimized"' "$optimized/terraform/environment/main.tf"
