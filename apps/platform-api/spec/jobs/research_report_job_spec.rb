require "rails_helper"

RSpec.describe ResearchReportJob do
  it "runs the report stages in order" do
    report = instance_double(Report, status: "queued")
    allow(Report).to receive(:find).with("report-1").and_return(report)
    input = { "report_id" => "report-1", "workflow_id" => "report-report-1", "correlation_id" => "request-1" }
    evidence = { "symbol" => "AAPL", "evidence" => [] }
    generation = { "payload" => {}, "model" => "gemini-3.8-flash", "prompt_version" => "v1", "usage" => {} }
    start_activity = instance_double(Reports::StartReportActivity, execute: {})
    evidence_activity = instance_double(Reports::LoadReportEvidenceActivity, execute: evidence)
    generation_activity = instance_double(Reports::GenerateReportActivity, execute: generation)
    persist_activity = instance_double(Reports::PersistReportActivity, execute: { "status" => "completed" })
    allow(Reports::StartReportActivity).to receive(:new).and_return(start_activity)
    allow(Reports::LoadReportEvidenceActivity).to receive(:new).and_return(evidence_activity)
    allow(Reports::GenerateReportActivity).to receive(:new).and_return(generation_activity)
    allow(Reports::PersistReportActivity).to receive(:new).and_return(persist_activity)

    described_class.perform_now(input)

    expect(start_activity).to have_received(:execute).with(input).ordered
    expect(evidence_activity).to have_received(:execute).with(input).ordered
    expect(generation_activity).to have_received(:execute).with(input.merge("evidence" => evidence)).ordered
    expect(persist_activity).to have_received(:execute)
      .with(input.merge("evidence" => evidence, "generation" => generation)).ordered
  end

  it "does not generate a cancelled report" do
    allow(Report).to receive(:find).with("report-1").and_return(instance_double(Report, status: "cancelled"))
    allow(Reports::StartReportActivity).to receive(:new)

    described_class.perform_now({ "report_id" => "report-1" })

    expect(Reports::StartReportActivity).not_to have_received(:new)
  end
end
