use std::{sync::Arc, time::Duration};

use async_trait::async_trait;
use tokio::{sync::watch, time};
use tracing::warn;

use crate::{
    event::NormalizedEvent,
    health::ServiceHealth,
    kafka::{EventPublisher, KafkaError},
    persistence::{PostgresStore, StoreError},
    streaming::StreamHub,
};

pub struct PostgresPublisher {
    store: Arc<PostgresStore>,
}

impl PostgresPublisher {
    pub fn new(store: Arc<PostgresStore>) -> Self {
        Self { store }
    }
}

#[async_trait]
impl EventPublisher for PostgresPublisher {
    async fn publish(&self, events: &[NormalizedEvent]) -> Result<(), KafkaError> {
        for event in events {
            self.store.persist_direct(event).await?;
        }
        Ok(())
    }
}

pub async fn run_journal_fanout(
    store: Arc<PostgresStore>,
    hub: Arc<StreamHub>,
    health: Arc<ServiceHealth>,
    replay_capacity: usize,
    mut shutdown: watch::Receiver<bool>,
) -> Result<(), StoreError> {
    let mut cursor = store.journal_start(replay_capacity).await?;
    let mut polling = time::interval(Duration::from_millis(250));
    loop {
        tokio::select! {
            changed = shutdown.changed() => {
                if changed.is_err() || *shutdown.borrow() { return Ok(()); }
            }
            _ = polling.tick() => {
                let rows = match store.journal_after(cursor, 1000).await {
                    Ok(rows) => rows,
                    Err(error) => {
                        health.set_kafka_ready(false);
                        return Err(error);
                    }
                };
                for (sequence, topic, payload) in rows {
                    match NormalizedEvent::decode(&topic, &payload).and_then(|event| event.live_event()) {
                        Ok(event) => hub.publish(event),
                        Err(error) => warn!(%error, sequence, "persisted market event could not be fanned out"),
                    }
                    cursor = sequence;
                }
                health.set_kafka_ready(true);
            }
        }
    }
}
