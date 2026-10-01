require "rails_helper"

RSpec.describe Events::PostgresOutboxDispatcher do
  let(:user) do
    User.create!(issuer: "fixture", external_subject: SecureRandom.uuid, email: "direct@example.test",
      display_name: "Direct")
  end
  let(:report) { user.reports.create!(symbol: "AAPL", title: "AAPL research report") }
  let(:event) do
    OutboxEvent.create!(topic: "reports.lifecycle.v1", aggregate_type: "Report", aggregate_id: report.id,
      payload: { envelope: Events::Envelope.build(event_id: SecureRandom.uuid, event_type: "report.queued",
        tenant_id: user.id, correlation_id: SecureRandom.uuid, idempotency_key: SecureRandom.uuid),
        report_id: report.id, workflow_id: "report-#{report.id}", status: "queued" })
  end

  it "dispatches a committed report once and acknowledges the outbox row" do
    event
    allow(ResearchReportJob).to receive(:perform_later)
    expect(described_class.new.publish_batch(limit: 1)).to eq(1)
    expect(event.reload.published_at).to be_present
    expect(report.reload.workflow_id).to eq("report-#{report.id}")
    expect(ResearchReportJob).to have_received(:perform_later).once
    expect(described_class.new.publish_batch(limit: 1)).to eq(0)
  end

  it "retains a failed enqueue with bounded retry metadata" do
    event
    allow(ResearchReportJob).to receive(:perform_later).and_raise("queue unavailable")
    expect(described_class.new.publish_batch(limit: 1)).to eq(0)
    expect(event.reload).to have_attributes(published_at: nil, attempts: 1, last_error: "RuntimeError")
    expect(event.next_attempt_at).to be > Time.current
  end

  it "does not dispatch an event for another tenant" do
    payload = event.payload
    payload["envelope"]["tenant_id"] = SecureRandom.uuid
    event.update!(payload: payload)
    allow(ResearchReportJob).to receive(:perform_later)
    expect(described_class.new.publish_batch(limit: 1)).to eq(0)
    expect(event.reload.published_at).to be_nil
    expect(ResearchReportJob).not_to have_received(:perform_later)
  end
end
