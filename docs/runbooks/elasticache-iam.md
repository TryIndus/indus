# ElastiCache IAM authentication

Platform API and Sidekiq connect to the environment's dedicated ElastiCache
Serverless cache over verified TLS. Their service accounts receive separate
IRSA roles; only those roles can call `elasticache:Connect`, and the policy is
scoped to the exact cache and IAM-enabled Valkey user. Redis ACLs allow the
commands required by Sidekiq 8 and no administrative or dangerous command.

No Redis password belongs in Secrets Manager or GitOps. Terraform outputs the
non-secret endpoint, port, cache name, and user name. `scripts/hydrate-gitops.rb`
copies those values into the environment overlay, and the chart supplies:

- `REDIS_AUTH_MODE=iam`
- `REDIS_ENDPOINT` and `REDIS_PORT`
- `REDIS_IAM_CACHE_NAME` and `REDIS_IAM_USER`
- `AWS_REGION`

Rails resolves rotating AWS credentials through the standard SDK chain, which
uses the projected IRSA web-identity token in EKS. Every new or re-established
Redis connection invokes the password provider and signs a new 15-minute
SigV4 token. Do not cache, log, trace, or expose the signed token. ElastiCache
can close long-lived IAM connections after 12 hours; redis-client reconnects
with a newly signed token for both the Sidekiq client and server pools.

## Offline verification

Run these checks before reviewing a plan. They do not contact AWS, Kubernetes,
Redis, or any production service.

```sh
cd apps/platform-api
bundle exec rspec spec/lib/redis_runtime_spec.rb
bundle exec rubocop lib/redis_runtime.rb spec/lib/redis_runtime_spec.rb config/initializers/sidekiq.rb
cd ../..
helm lint infra/helm/indus-platform
helm template indus infra/helm/indus-platform \
  --values infra/gitops/environments/development/values.yaml >/tmp/indus-platform.yaml
terraform fmt -check -recursive infra/terraform
scripts/validate-phase4.sh
```

In rendered manifests, confirm platform-api and Sidekiq have the five Redis IAM
variables and no `REDIS_URL` secret projection. Confirm other service accounts
cannot assume either role. In a reviewed Terraform plan, confirm the
`elasticache:Connect` policy includes exactly the cache ARN and user ARN, and
the user ID equals its username as ElastiCache IAM requires.

## Deployment and rollback

Roll out to development first. Check Sidekiq startup, enqueue one synthetic
job through platform-api, and wait for successful completion. Monitor
authentication errors, reconnects, queue latency, and ElastiCache connections
through at least one credential refresh window before promotion. Repeat in
staging before production.

Authentication failure is fail-closed: do not add a static production
password or disable TLS verification. Roll back the workload digest and GitOps
values together. If Terraform changed the cache user, keep the prior user in
the group and its narrowly scoped role policy until the previous workload is
fully drained; remove it only in a later reviewed apply. Local Compose is not
affected and continues to use `REDIS_AUTH_MODE=url` implicitly with
`REDIS_URL=redis://redis:6379/0`.
