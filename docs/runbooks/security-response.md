# Security response and access review

Severity one includes tenant data exposure, credential disclosure, privileged
pod admission, unsigned production image, KMS misuse, or unauthorized DNS/IAM
change. Roll traffic back, isolate the affected workload, preserve CloudTrail,
WAF, EKS audit, application, and registry evidence, and rotate only the exposed
boundary. Do not destroy pods or logs before capture unless containment demands
it.

Monthly: review IAM Access Analyzer, CloudTrail anomalies, Secrets Manager
access, KMS grants, EKS access entries, Argo admins, GitHub environment
reviewers, ECR findings, Dependabot, WAF samples, public endpoints, and stale
roles. Quarterly: exercise key/secret rotation, restore, break-glass MFA access,
network-policy denial, unsigned-image rejection, and compromised workload IRSA
containment. Production release blocks on any unresolved critical finding.

Break-glass cluster admin requires MFA and an audited role assumption. It is
not used by CI or Argo. Remove temporary access immediately and attach the
CloudTrail event ID to the incident record.
