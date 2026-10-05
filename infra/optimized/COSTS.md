# Optimized profile cost worksheet

Fill this worksheet with current regional AWS pricing and measured usage before
commissioning the profile. It is an inventory, not an estimate or billing
claim. During a migration rehearsal, include the temporary overlap with main.

| Component | Usage input to collect | Notes |
| --- | --- | --- |
| EC2 | `t3a.small` instance-hours and CPU burst credits | Includes the Docker host. |
| EBS and public IPv4 | gp3 GiB, IOPS/throughput if changed, snapshots, IPv4 hours | Valkey data occupies host EBS. |
| RDS | `db.t4g.micro` hours, gp3 GiB, backups, I/O if applicable | Single-AZ is not a standby. |
| S3 | artifact GiB-months, requests, retrieval/transfer | Versioning and lifecycle affect retained bytes. |
| Cognito and SES | monthly active users and branded-email sends | SES is optional and disabled initially. |
| ECR | image GiB-months and image pulls | Four optimized repositories are separate from main. |
| CloudWatch | basic metrics, and optional agent metrics and alarms | `enable_supplementary_monitoring` defaults to `false`; local Docker logs remain bounded. |
| Secrets Manager and KMS | secrets, API calls, KMS requests | Runtime secret containers are separate. |
| Route 53 | one `tryindus.ca` hosted zone, queries, optional health checks | The retired optimized subdomain hosted zone is not required. |
| Data transfer | internet egress, cross-AZ traffic, external provider traffic | EC2 and RDS remain in AZ A by design. |
| Overlap | duration and all main plus optimized line items | Merging this configuration does not reduce current spend. |
