ALTER TABLE market_data.consumed_events
  ALTER COLUMN partition_id DROP NOT NULL,
  ALTER COLUMN offset_id DROP NOT NULL;

CREATE TABLE market_data.direct_event_journal (
  sequence bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  event_id uuid NOT NULL UNIQUE REFERENCES market_data.consumed_events(event_id) ON DELETE CASCADE,
  topic text NOT NULL CHECK (topic IN ('market.bars.v1', 'market.quotes.v1')),
  payload bytea NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX direct_event_journal_recorded_idx ON market_data.direct_event_journal (recorded_at);
REVOKE ALL ON market_data.direct_event_journal FROM PUBLIC;
