# Event transport modes

Production uses Kafka on MSK for report lifecycle delivery and market-data events (`EVENT_TRANSPORT=kafka`). PostgreSQL is an optional transport (`EVENT_TRANSPORT=postgres`) that uses the existing Aurora database and Sidekiq worker. Both implementations remain in the codebase; the configured mode determines which one handles events.

Before enabling PostgreSQL mode, back up Aurora and record the deployed image digests, outbox backlog, Kafka consumer lag, and rollback point. The Rust service applies its additive SQL migration on startup. Verify `market_data.direct_event_journal` exists and Kafka mode serves charts and reports before switching.

Set `config.eventTransport: postgres` and `reportsConsumer.replicas: 0` together in GitOps. Keep `platformOutbox.replicas: 1`. Check that Rails and Rust pods report ready, report outbox rows gain `published_at`, report jobs complete, bars and quotes gain journal rows without Kafka offsets, and stock and crypto SSE streams update and reconnect. Check two market-data pods before allowing autoscaling above one. Monitor Aurora connections, CPU, storage, and query latency.

Returning to Kafka mode requires reconciling events written only to the PostgreSQL journal first; changing the flag alone would leave a market-data gap. Preserve the Kafka broker configuration and verify the outbox and consumer lag after the switch. Changing the transport mode does not change the MSK infrastructure.

After production PostgreSQL mode is healthy, set `enable_msk = false` in the production Terraform module and run the infrastructure workflow's `plan` operation. Confirm the plan removes the MSK cluster and its Kafka workload IAM policies without changing Aurora or application resources, then run `apply`. The module defaults to `enable_msk = true` for environments using Kafka. To restore Kafka, set it back to true, apply infrastructure, update the broker address in GitOps, reconcile PostgreSQL-only journal events, and then change `EVENT_TRANSPORT` back to `kafka`.
