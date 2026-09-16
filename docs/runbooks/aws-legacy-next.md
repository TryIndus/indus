# AWS deployment of the current application

## Release contract

Build the root `Dockerfile` with the two publishable Supabase build arguments.
The final image runs `node server.js` as UID 1001 and contains no provider
credentials. Supply provider values only through the one `legacy-next`
Secrets Manager secret.

The workload is rendered by `infra/helm/indus-legacy-next`. It requires an
immutable image digest, workload role ARN, runtime secret ARN, target group
ARN, and region from Terraform outputs. It runs readiness probes against
`/api/health?mode=ready`; a failed provider configuration prevents new traffic
from reaching the pod.

## Cutover and rollback

1. Run the explicit staging infrastructure plan and apply from `staging`, then
   deploy the application from `staging`.
2. Store the five required values in the production `legacy-next` secret and
   confirm the pod role can read only it.
3. Merge the reviewed `staging` branch into `main`, then deploy the application
   and infrastructure explicitly from `main`. Wait for Argo CD, CloudFront, ALB
   target health, authenticated browser smoke tests, and accessibility tests.
4. Increase Route 53 `aws_traffic_weight` gradually from the Vercel origin to
   CloudFront. Stop if readiness, authentication, provider errors, or client
   error rates regress.
5. Roll back by returning DNS weight to Vercel or restoring the previous
   signed image.
