# SLO incident response

All alerts must include service, severity, symptom, and this runbook. Page on
user-visible symptoms or fast error-budget burn; ticket slow capacity trends.

## Platform API

Check CloudFront/WAF/ALB target errors, Rails RED metrics, RDS Proxy saturation,
Aurora connections/CPU, Redis health, dependency latency, and the last digest.
Protect data first: roll back traffic or image before deep diagnosis when 5xx
exceeds 2% or p95 exceeds 500 ms.

## Market data

For stale feed or delay above five seconds, identify provider versus internal
lag, inspect reconnect/heartbeat metrics, MSK offsets, rejected versions, and
consumer backpressure. Disable ingestion before replay if duplicates cannot be
proven idempotent. Any acknowledged-event loss is a page and cutover abort.

## Report workflows

Check Temporal availability, task queue depth, retry/deadline reasons, Gemini
dependency status, artifact writes, and lifecycle-event consumption. Do not
manually restart workflow IDs without idempotency evidence. Terminal success or
actionable failure must remain at least 99% within ten minutes.

## Security or tenant isolation

Immediately set replacement traffic to zero, preserve CloudTrail/WAF/EKS audit
evidence, revoke the narrow credential or role session, and follow
`security-response.md`. Never place tokens, prompts, or provider payloads in the
incident channel.
