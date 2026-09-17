#!/usr/bin/env bash
set -euo pipefail

environment="${1:-}"
case "$environment" in
  staging) revision=staging ;;
  production) revision=main ;;
  *) echo "Usage: $0 <staging|production>" >&2; exit 1 ;;
esac

: "${AWS_REGION:?Set AWS_REGION to the environment AWS region.}"

root="$(cd "$(dirname "$0")/../.." && pwd)"
terraform_root="$root/infra/terraform/environments/$environment"
if [[ -n "${TERRAFORM_OUTPUT_JSON:-}" ]]; then
  infrastructure="$TERRAFORM_OUTPUT_JSON"
else
  infrastructure="$(terraform -chdir="$terraform_root" output -json environment)"
fi

jq -n \
  --arg environment "$environment" \
  --arg revision "$revision" \
  --arg region "$AWS_REGION" \
  --arg repository "https://github.com/TryIndus/indus.git" \
  --argjson infrastructure "$infrastructure" \
  '{
    apiVersion: "argoproj.io/v1alpha1",
    kind: "Application",
    metadata: {
      name: "indus-applications",
      namespace: "argocd",
      finalizers: ["resources-finalizer.argocd.argoproj.io"]
    },
    spec: {
      project: "default",
      source: {
        repoURL: $repository,
        targetRevision: $revision,
        path: "infra/helm/indus-applications",
        helm: {
          valuesObject: {
            environment: $environment,
            repository: $repository,
            revision: $revision,
            clusterName: $infrastructure.cluster.name,
            vpcId: $infrastructure.cluster.vpc_id,
            awsRegion: $region,
            roles: {
              loadBalancer: $infrastructure.workload_role_arns["aws-load-balancer-controller"]
            },
            legacyNext: {
              enabled: true,
              imageRepository: $infrastructure.shared_ecr_repository_urls["legacy-next"],
              serviceAccountRoleArn: $infrastructure.workload_role_arns["legacy-next"],
              runtimeSecretArn: $infrastructure.secret_arns.legacy_next,
              targetGroupArn: $infrastructure.edge.legacy_next_target_group_arn
            },
            platform: { enabled: false }
          }
        }
      },
      destination: {
        server: "https://kubernetes.default.svc",
        namespace: "argocd"
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true },
        syncOptions: ["ServerSideApply=true"]
      }
    }
  }'
