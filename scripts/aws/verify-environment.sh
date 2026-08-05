#!/usr/bin/env bash
set -euo pipefail

environment="${1:-}"
mode="${2:-}"
[[ "$environment" =~ ^(development|staging|production)$ ]] || {
  echo "Usage: $0 ENVIRONMENT [--execute-read-only]" >&2
  exit 2
}

if [[ "$mode" != "--execute-read-only" ]]; then
  echo "Dry run: would read Terraform outputs, EKS health, Argo sync, target health, backups, and alarms for $environment."
  echo "No AWS, DNS, Kubernetes, or application state changed."
  exit 0
fi

for command in aws jq kubectl terraform; do command -v "$command" >/dev/null 2>&1 || exit 1; done
terraform_root="infra/terraform/environments/$environment"
outputs="$(terraform -chdir="$terraform_root" output -json environment)"
cluster="$(jq -r '.cluster.name' <<<"$outputs")"
distribution="$(jq -r '.edge.cloudfront_distribution_id' <<<"$outputs")"

aws eks describe-cluster --name "$cluster" --query 'cluster.{name:name,status:status,version:version,endpointPublicAccess:resourcesVpcConfig.endpointPublicAccess}'
aws cloudfront get-distribution --id "$distribution" --query 'Distribution.{Status:Status,Enabled:DistributionConfig.Enabled,DomainName:DomainName}'
aws backup list-recovery-points-by-backup-vault --backup-vault-name "$cluster" --max-results 5 \
  --query 'RecoveryPoints[].{Status:Status,Created:CreationDate,ResourceType:ResourceType}'
aws cloudwatch describe-alarms --alarm-name-prefix "$cluster" --query 'MetricAlarms[].{Name:AlarmName,State:StateValue}'
kubectl get applications.argoproj.io -n argocd
kubectl get deployments,jobs,pods -n indus
kubectl get targetgroupbindings.elbv2.k8s.aws -n indus
