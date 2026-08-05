require "rails_helper"

RSpec.describe Events::OutboxPublisher do
  let(:now) { Time.zone.parse("2026-08-05T12:00:00Z") }
  let(:clock) { class_double(Time, current: now) }
  let(:producer) { instance_double(Events::KafkaProducer, publish: true) }
  let(:event) do
    OutboxEvent.create!(topic: "reports.lifecycle.v1", aggregate_type: "Report", aggregate_id: SecureRandom.uuid,
      payload: { envelope: Events::Envelope.build(event_id: SecureRandom.uuid, event_type: "report.queued",
        tenant_id: SecureRandom.uuid, correlation_id: SecureRandom.uuid, idempotency_key: SecureRandom.uuid) })
  end

  it "acknowledges an outbox row only after Kafka acknowledges it" do
    expect(described_class.new(producer: producer, clock: clock).publish_one(event.id)).to be(true)
    expect(event.reload).to have_attributes(published_at: now, attempts: 1, last_error: nil)
    expect(producer).to have_received(:publish).with(hash_including(topic: "reports.lifecycle.v1", key: event.aggregate_id))
  end

  it "retains failed rows with bounded retry metadata" do
    allow(producer).to receive(:publish).and_raise(StandardError, "broker unavailable")
    expect(described_class.new(producer: producer, clock: clock).publish_one(event.id)).to be(false)
    expect(event.reload).to have_attributes(published_at: nil, attempts: 1, last_error: "StandardError")
    expect(event.next_attempt_at).to eq(now + 2.seconds)
  end
end
