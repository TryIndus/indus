use indus_market_data::{
    direct::run_journal_fanout,
    event::NormalizedEvent,
    health::ServiceHealth,
    kafka::KafkaRecord,
    persistence::{EventStore, PersistOutcome, PostgresStore},
    provider::{FeedKind, parse_message},
    streaming::StreamHub,
};
use std::{sync::Arc, time::Duration};

#[tokio::test]
async fn duplicate_reordered_and_unsupported_events_are_explicit() {
    let Ok(database_url) = std::env::var("TEST_DATABASE_URL") else {
        eprintln!("skipping PostgreSQL integration test: TEST_DATABASE_URL is unset");
        return;
    };
    let store = PostgresStore::connect(&database_url).await.unwrap();
    let mut events = parse_message(
        include_str!("fixtures/alpaca_equity.json"),
        FeedKind::Equity,
    )
    .unwrap();
    events.reverse();
    for (offset, event) in events.iter().enumerate() {
        let record = record(event, offset as i64);
        assert_eq!(
            store.persist(&record).await.unwrap(),
            PersistOutcome::Stored
        );
    }
    let duplicate = record(&events[0], 50);
    assert_eq!(
        store.persist(&duplicate).await.unwrap(),
        PersistOutcome::Duplicate
    );

    let mut unsupported = events[1].clone();
    match &mut unsupported {
        NormalizedEvent::Bar(event) => event.envelope.as_mut().unwrap().schema_version = 999,
        NormalizedEvent::Quote(event) => event.envelope.as_mut().unwrap().schema_version = 999,
    }
    let rejected = record(&unsupported, 51);
    assert_eq!(
        store.persist(&rejected).await.unwrap(),
        PersistOutcome::Rejected
    );

    let mut invalid_id = events[0].clone();
    invalid_id.envelope_mut().event_id = "not-a-uuid".into();
    assert_eq!(
        store.persist(&record(&invalid_id, 52)).await.unwrap(),
        PersistOutcome::Rejected
    );

    let mut missing_timestamp = events[1].clone();
    missing_timestamp.envelope_mut().occurred_at = None;
    assert_eq!(
        store
            .persist(&record(&missing_timestamp, 53))
            .await
            .unwrap(),
        PersistOutcome::Rejected
    );
}

#[tokio::test]
async fn direct_events_commit_without_kafka_offsets_and_replay_from_the_journal() {
    let Ok(database_url) = std::env::var("TEST_DATABASE_URL") else {
        eprintln!("skipping PostgreSQL integration test: TEST_DATABASE_URL is unset");
        return;
    };
    let store = Arc::new(PostgresStore::connect(&database_url).await.unwrap());
    let pool = sqlx::PgPool::connect(&database_url).await.unwrap();
    let mut events = parse_message(
        include_str!("fixtures/alpaca_crypto.json"),
        FeedKind::Crypto,
    )
    .unwrap();
    let event = events.pop().unwrap();
    let mut event = event;
    let unique = format!("{}-{:?}", std::process::id(), std::time::SystemTime::now());
    event.envelope_mut().event_id =
        uuid::Uuid::new_v5(&uuid::Uuid::NAMESPACE_URL, unique.as_bytes()).to_string();
    let id = uuid::Uuid::parse_str(&event.envelope().unwrap().event_id).unwrap();
    let cursor = sqlx::query_scalar::<_, i64>(
        "SELECT COALESCE(MAX(sequence), 0) FROM market_data.direct_event_journal",
    )
    .fetch_one(&pool)
    .await
    .unwrap();

    assert_eq!(
        store.persist_direct(&event).await.unwrap(),
        PersistOutcome::Stored
    );
    assert_eq!(
        store.persist_direct(&event).await.unwrap(),
        PersistOutcome::Duplicate
    );
    let position = sqlx::query_as::<_, (Option<i32>, Option<i64>)>(
        "SELECT partition_id, offset_id FROM market_data.consumed_events WHERE event_id = $1",
    )
    .bind(id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(position, (None, None));
    let journal = store.journal_after(cursor, 10).await.unwrap();
    assert_eq!(journal.len(), 1);
    assert_eq!(
        NormalizedEvent::decode(&journal[0].1, &journal[0].2)
            .unwrap()
            .envelope()
            .unwrap()
            .event_id,
        id.to_string()
    );

    let hub = Arc::new(StreamHub::new(16, 16, Duration::from_secs(30)));
    let health = Arc::new(ServiceHealth::default());
    health.set_postgres_transport(true);
    let (shutdown, receiver) = tokio::sync::watch::channel(false);
    let fanout = tokio::spawn(run_journal_fanout(
        store,
        hub.clone(),
        health.clone(),
        16,
        receiver,
    ));
    tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            if !hub.subscribe(event.symbol(), None).replay.is_empty()
                && health.readiness().transport == "ready"
            {
                break;
            }
            tokio::time::sleep(Duration::from_millis(25)).await;
        }
    })
    .await
    .unwrap();
    let replay = hub.subscribe(event.symbol(), Some("missing-cursor"));
    assert!(replay.replay_gap);
    assert!(replay.replay.iter().any(|entry| entry.id == id.to_string()));
    shutdown.send(true).unwrap();
    fanout.await.unwrap().unwrap();
}

trait EnvelopeMut {
    fn envelope_mut(&mut self) -> &mut indus_market_data::event::EventEnvelope;
}

impl EnvelopeMut for NormalizedEvent {
    fn envelope_mut(&mut self) -> &mut indus_market_data::event::EventEnvelope {
        match self {
            NormalizedEvent::Bar(event) => event.envelope.as_mut().unwrap(),
            NormalizedEvent::Quote(event) => event.envelope.as_mut().unwrap(),
        }
    }
}

fn record(event: &NormalizedEvent, offset: i64) -> KafkaRecord {
    KafkaRecord {
        topic: event.topic().into(),
        payload: event.encode(),
        event_id: Some(event.envelope().unwrap().event_id.clone()),
        // Cargo executes integration-test binaries concurrently. Keep this
        // synthetic database fixture disjoint from the live Kafka test,
        // which consumes the broker-assigned partition zero.
        partition: 32_767,
        offset,
    }
}
