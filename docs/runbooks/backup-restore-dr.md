# Backup, restore, and regional recovery

Aurora continuous backup targets a five-minute RPO and 60-minute same-region
RTO. Daily AWS Backup copies of tagged Aurora, S3, and EBS resources go to an
encrypted `us-east-1` vault; regional disaster objectives are 24-hour RPO and
four-hour RTO. S3 versioning protects operator overwrite. Redis is disposable;
Kafka state is recovered from transactional data/outbox and archived raw
events, not from cache or broker assumptions.

Quarterly restore rehearsal:

1. Select a recovery point without modifying the source. Record ARN, creation
   time, source checksum, and expected RPO.
2. Restore into a new, isolated subnet/security group and a unique rehearsal
   name. Never restore over an existing cluster or bucket.
3. Use separate credentials; run migrations only if the selected application
   digest requires them. Validate schema, constraints, tenant isolation, row and
   checksum reconciliation, sampled artifacts, query plans, and application
   smoke tests.
4. Record time-to-data and time-to-service. Rehearsal fails if RPO/RTO or any
   integrity check misses. Retain evidence, then delete only the explicitly
   named rehearsal resources after a second operator confirms the target.

Regional recovery applies the environment Terraform in the recovery region,
restores cross-region copies into new resources, replays archived events from
the recorded high-water mark, validates Cognito configuration and signed
images, then changes weighted DNS only after the cutover evaluator passes.
KMS keys and vault locks must remain recoverable. Run `verify-environment.sh`
read-only before and after every exercise.
