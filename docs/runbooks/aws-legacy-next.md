# AWS deployment of the current application

This runbook moves the current Next.js application from Vercel to AWS without
changing its product or provider boundaries. Supabase remains the identity and
database provider; Alpaca, Yahoo Finance, and Gemini remain provider
boundaries.

The Phase 1 runtime is `us-east-1` only. CloudFront is in front of the
application and connects over HTTPS to the ALB. The ALB
occupies two public subnets as required by AWS, while the one EKS worker node
and its workload live only in the primary private subnet. Cross-zone ALB
routing reaches that primary target from either ALB subnet.

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

1. Apply staging, review its Terraform plan and acceptance checks, then apply
   production from a separately reviewed plan.
2. Store the five required values in the production `legacy-next` secret and
   confirm the pod role can read only it.
3. Promote the same signed image from staging to production. Wait for Argo CD,
   CloudFront, ALB target health, authenticated browser smoke tests, and
   accessibility tests.
4. Increase Route 53 `aws_traffic_weight` gradually from the Vercel origin to
   CloudFront. Stop if readiness, authentication, provider errors, or client
   error rates regress.
5. Roll back by returning DNS weight to Vercel or restoring the previous
   signed image.

## Accepted reliability boundary

The application data plane is single-AZ and single-node. A primary AZ, NAT,
node, or pod outage makes the environment unavailable. The secondary ALB subnet
exists solely to meet ALB requirements and preserve edge connectivity; it has
no workload targets. Do not represent this design as highly available.
