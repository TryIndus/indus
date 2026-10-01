module Events
  class PostgresOutboxDispatcher
    BATCH_SIZE = 100
    MAX_BACKOFF = 300

    def initialize(clock: Time)
      @clock = clock
    end

    def publish_batch(limit: BATCH_SIZE)
      published = 0
      limit.times do
        processed = false
        OutboxEvent.transaction do
          event = OutboxEvent.unpublished.lock("FOR UPDATE SKIP LOCKED").first
          next unless event

          processed = true
          begin
            raise ArgumentError, "unsupported event topic" unless event.topic == "reports.lifecycle.v1"

            Events::Envelope.validate!(event.payload)
            raise ArgumentError, "report aggregate does not match event" unless event.aggregate_type == "Report" && event.aggregate_id.to_s == event.payload.fetch("report_id").to_s
            Reports::EventHandler.call(event.payload)
            event.update!(published_at: @clock.current, attempts: event.attempts + 1,
              next_attempt_at: nil, last_error: nil)
            published += 1
          rescue StandardError => error
            attempts = event.attempts + 1
            delay = [ 2**[ attempts, 8 ].min, MAX_BACKOFF ].min
            event.update!(attempts: attempts, next_attempt_at: @clock.current + delay.seconds,
              last_error: error.class.name.to_s.byteslice(0, 120))
          end
        end
        break unless processed
      end
      published
    end
  end
end
