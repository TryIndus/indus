#!/usr/bin/env bash
set -euo pipefail

optimized=infra/optimized
[[ -d "$optimized" ]]
! rg -n --hidden --glob '!*.example' 'terraform_remote_state|environments/production/terraform\.tfstate|indus-production|indus-staging' "$optimized"
! rg -n 'aws_eks_|aws_rds_cluster|aws_db_proxy|aws_msk_|aws_elasticache_|aws_lb|aws_cloudfront_|aws_nat_gateway' "$optimized/terraform"
! git diff --name-only origin/main...HEAD | rg '^infra/terraform/'
rg -q 'optimized/production/terraform.tfstate' "$optimized/terraform/environment/backend.hcl.example"
rg -q 'Profile *= *"optimized"' "$optimized/terraform/environment/main.tf"
