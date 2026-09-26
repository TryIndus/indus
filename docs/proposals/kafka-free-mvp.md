# Proposed Kafka-free MVP runtime

Status: design draft; no runtime, database, deployment, or cloud-resource changes are implemented by this document. The current architecture documents remain descriptions of the existing system. This proposal targets the high fixed cost of MSK without changing the product UI, HTTP contracts, Cognito authentication, tenant authorization, Gemini boundary, or research features.

## Cost and scope

AWS Cost Explorer for the Indus member account on September 25, 2026 showed US$18/day for one MSK Serverless cluster, or about US$540 per 30 days before tax. Charged Kafka data traffic was small compared with the cluster charge. Eliminating the cluster has the largest identified savings, but PostgreSQL processing, storage, and connection usage will increase; measure those costs before promising net savings.

The first implementation milestone replaces Kafka's two active roles: report lifecycle delivery and Rust market-event durability. Keep EKS, Aurora, Sidekiq/Valkey, CloudFront, S3, Cognito, and Secrets Manager during this milestone. No Temporal Cloud namespace is required: the deployed Rails queue adapter is Sidekiq. Existing Temporal code and placeholder configuration must not be mistaken for an active cloud dependency.

Replacing EKS with a simpler container deployment is a later infrastructure change with its own review and rollback. Replacing Sidekiq with Solid Queue is also deferred: the observed Valkey cost was only about US$6/month, and combining queue replacement with broker removal makes recovery harder to assess. This draft does not depend on the separate RDS Proxy/logging PR and branches directly from `main`.

## Existing coupling to replace

| Boundary | Implementation today | Proposed replacement |
|---|---|---|
| Rails domain state | Domain write, audit row, and outbox row commit together | Keep the transaction and versioned envelopes |
| Report delivery | `Events::OutboxPublisher` publishes to Kafka; `Reports::EventConsumer` records a receipt and enqueues `ResearchReportJob` in Sidekiq | A leased PostgreSQL dispatcher hands report requests to the existing job system, with explicit duplicate tolerance |
| Report execution | `ResearchReportJob` calls persistent report activities | Keep cancellation, retries, terminal states, activity leases, evidence validation, and immutable S3 artifacts |
| Market ingestion | Rust batches normalized events, publishes transactionally to Kafka, then broadcasts SSE | Commit validated normalized events and a durable publication journal in PostgreSQL before broadcasting |
| Market storage | Kafka consumer inserts deduplicated event receipts and partitioned bars/quotes | Transport-neutral storage with event-ID deduplication and additive schema changes |
| SSE replay | `StreamHub` holds a bounded replay buffer in memory | Keep the buffer and public event IDs; recover persisted publication history after restart and emit an explicit gap when a cursor is outside retention |

The current `market_data.consumed_events` and `rejected_events` schemas require Kafka partition and offset metadata. Direct ingestion must not invent fake Kafka offsets or edit the applied `0001_market_data.sql` migration.

## Rails delivery design

Add a forward-only migration for dispatcher claims: lease owner, lease expiry, and bounded retry/dead-letter metadata. Preserve the existing event UUID and domain/outbox transaction. Claims use short PostgreSQL transactions and `FOR UPDATE SKIP LOCKED`; no model or Redis call runs while holding a database row lock.

The dispatch sequence is claim, validate envelope and topic, enqueue the existing report job, and acknowledge with the matching lease owner. If Redis rejects an enqueue, the row remains retryable. If a process dies after enqueue but before acknowledgment, retry can enqueue a duplicate. Do not mark the outbox delivered before Redis acknowledges, and do not advertise exactly-once delivery across PostgreSQL and Redis.

Retain durable report/activity deduplication. Exercise duplicate jobs during an active lease, after lease expiry, after artifact creation, after completion, and after cancellation. A stale dispatcher cannot acknowledge a lease reclaimed by another process. Completed activity results are reused; failed or expired work can resume. An external model timeout may still have incurred a provider charge, so no claim of exactly-once model execution is made.

Inventory every emitted topic and current consumer before enabling direct delivery. Explicitly register supported handlers and local audit-only delivery policies. Unknown topics and unsupported schemas must remain visible and retryable or dead-lettered; they must never be silently marked published. Domain auditing and tenant ownership remain independent of the delivery transport.

Use bounded exponential retries and an operator replay command scoped by event ID. Emit aggregate backlog age, attempts, dead-letter count, and dispatcher-health metrics without payloads or credentials. Database unavailability leaves authoritative state untouched and causes worker readiness to fail.

## Rust durability and fanout design

Introduce a transport-neutral persistence API for normalized events. Add separate direct-ingestion receipts and a publication journal through a sequential SQL migration, keeping the existing Kafka consumer and tables compatible during migration. Receipt uniqueness is based on deterministic event UUIDs. Keep rejected-event storage bounded and transport-aware, without logging raw provider payloads.

A transaction validates and inserts the receipt, bar/quote, and normalized publication record atomically. Duplicate events acknowledge existing durable state without creating a second market row. Only successfully committed events can reach SSE. Do not return a generic success for malformed events and accidentally broadcast them: distinguish stored, duplicate, and rejected results.

The publisher retains failed batches for bounded retry and applies backpressure to ingestion. PostgreSQL availability becomes the durability prerequisite in direct mode; Kafka must not be part of readiness in that mode. Keep provider disconnect, stale data, queue saturation, and shutdown behavior observable. Shutdown before commit cannot be reported as an acknowledged event.

A publication reader fans out committed journal records. PostgreSQL notifications may wake the reader but are hints, not the source of truth. Polling and durable cursors recover missed notifications. Preserve per-symbol ordering under concurrent writes and failover; do not assume an ordinary sequence value alone guarantees transaction commit order. Choose and test an explicit ordering strategy before implementation is considered complete.

Each SSE-serving instance must see the required committed events, including instances that do not own the upstream feed. Keep authenticated per-user/global limits, subscription isolation, disconnect cleanup, bounded buffers, stale/gap events, and the existing browser reconnect behavior. A replay cursor that was pruned must yield an explicit gap, not silent omission. Stock and slash-delimited crypto symbols must use the same path.

Journal and receipt retention are bounded and coordinated with bar/quote retention. Do not prune receipts early enough to re-admit events still retained in market tables. Benchmark writes and replay at the intended provider subscription volume, not just an idle fixture.

## Implementation and verification gates

1. Inventory topics/consumers and characterize existing report and SSE contracts. Add the new migrations and bounded configuration with Kafka remaining the default. Validate both adapters independently without changing production.
2. Implement and test the Rails dispatcher, recovery, unknown-topic behavior, and duplicate/cancelled report execution. Run containerized RSpec, RuboCop, Brakeman, and Bundler Audit.
3. Implement direct Rust persistence, publication journal, cross-instance fanout, replay, retention, readiness, and backpressure. Run `bash scripts/verify-market-data.sh`; include real PostgreSQL transaction, restart, duplicate, malformed-event, database-outage, and cursor-gap tests.
4. Add a Kafka-free Compose mode and exercise dependency recovery through `bun run test:phase3`. Run the Chromium full-stack suite covering sign-in, tenant isolation, company data, charts, reports, favorites, retry, and stock/crypto search. The suite must wait for actual worker completion, not only creation of a queued report.
5. Run a two-instance market-data test, provider-volume load test, and connection-capacity check. Compare Aurora ACU, storage, IO, report latency, SSE latency/recovery, and error rates with the baseline. Define acceptable operational budgets before enabling direct delivery.
6. Review the complete code diff and production rollout plan. The draft remains unmergeable until both Rails and Rust have an operational Kafka-free path, CI passes, and failure-path evidence is recorded in the PR.

HTTP/event contracts remain unchanged unless a reviewed contract amendment is required. Regenerate committed clients if that happens. Migrations are forward-only; no existing shared migration is edited. This proposal does not authorize any merge, secret mutation, infrastructure apply, production data change, or cutover.

## Separate production rollout

Back up PostgreSQL and record the restore/forward-recovery point. Deploy additive migrations first, then immutable application images with Kafka mode still enabled. Validate the existing path before enabling direct modes for Rails and Rust. Never run both ingestion adapters against the same feed without a demonstrated deduplication and ordering strategy.

Keep Kafka available through the observation period. Drain old outbox work and Kafka consumer lag, account for rejected/dead-letter events, and verify report completion, chart freshness, SSE reconnects, tenant isolation, and restart recovery. Retain the old images, broker endpoints, consumer positions, and configuration as rollback points. Configuration rollback must include a journal catch-up/reconciliation strategy for events written only in direct mode; simply flipping back to Kafka would leave a gap.

Remove MSK only in a separate reviewed infrastructure change after no deployed workload, readiness check, publisher, or consumer depends on it. Preserve encrypted storage and database backups. Billing savings start after cluster deletion; until then the cluster continues to incur its fixed charge.

For a later EKS reduction, compare a small VM/container deployment with ECS using measured memory, CPU, SSE connection counts, image storage, and replacement network/load-balancer costs. Keep the React asset/CDN path and private database boundary. A single host reduces redundancy and adds host-maintenance duties; it cannot be presented as equivalent availability without recovery evidence.
