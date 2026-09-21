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
            platform: {
              enabled: $infrastructure.replacement_platform.enabled,
              values: {
                environment: $environment,
                aws: {
                  region: $region,
                  vpcCidr: $infrastructure.network.vpc_cidr,
                  webBucket: $infrastructure.data_platform.web_bucket,
                  cloudfrontDistributionId: $infrastructure.edge.cloudfront_distribution_id,
                  targetGroups: {
                    platformApi: $infrastructure.edge.platform_api_target_group_arn,
                    marketData: $infrastructure.edge.market_data_target_group_arn
                  }
                },
                identity: {
                  issuer: $infrastructure.identity.issuer,
                  audience: $infrastructure.identity.client_id,
                  userInfoUrl: $infrastructure.identity.userinfo_url
                },
                roles: {
                  platformApi: $infrastructure.workload_role_arns["platform-api"],
                  sidekiq: $infrastructure.workload_role_arns.sidekiq,
                  platformOutbox: $infrastructure.workload_role_arns["platform-outbox"],
                  reportsConsumer: $infrastructure.workload_role_arns["reports-consumer"],
                  marketData: $infrastructure.workload_role_arns["market-data"],
                  researchWorker: $infrastructure.workload_role_arns["research-worker"],
                  databaseMigrator: $infrastructure.workload_role_arns["database-migrator"],
                  webPublisher: $infrastructure.workload_role_arns["web-publisher"]
                },
                secrets: {
                  platformApi: $infrastructure.secret_arns.platform_api,
                  marketData: $infrastructure.secret_arns.market_data,
                  researchWorker: $infrastructure.secret_arns.research_worker,
                  databaseMigration: $infrastructure.secret_arns.database_migration
                },
                config: {
                  rdsProxyEndpoint: $infrastructure.data_platform.rds_proxy_endpoint,
                  redisEndpoint: $infrastructure.data_platform.redis_endpoint,
                  redisPort: $infrastructure.data_platform.redis_port,
                  redisCacheName: $infrastructure.data_platform.redis_cache_name,
                  redisUser: $infrastructure.data_platform.redis_user,
                  mskBootstrapBrokers: $infrastructure.data_platform.msk_bootstrap_brokers,
                  artifactBucket: $infrastructure.data_platform.artifacts_bucket,
                  rawEventsBucket: $infrastructure.data_platform.raw_events_bucket,
                  temporalAddress: $infrastructure.replacement_platform.temporal_address,
                  temporalNamespace: $infrastructure.replacement_platform.temporal_namespace
                }
              }
            }
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
