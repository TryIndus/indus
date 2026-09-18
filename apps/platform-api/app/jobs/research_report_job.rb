class ResearchReportJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :polynomially_longer, attempts: 5 do |job, error|
    job.send(:mark_failed, error)
  end

  def perform(input)
    return if Report.find(input.fetch("report_id")).status == "cancelled"

    Reports::StartReportActivity.new.execute(input)
    evidence = Reports::LoadReportEvidenceActivity.new.execute(input)
    generation = Reports::GenerateReportActivity.new.execute(input.merge("evidence" => evidence))
    Reports::PersistReportActivity.new.execute(input.merge("evidence" => evidence, "generation" => generation))
  rescue Reports::ReportCancelled
    Reports::MarkReportCancelledActivity.new.execute(input)
  end

  private

  def mark_failed(error)
    input = arguments.fetch(0)
    Reports::MarkReportFailedActivity.new.execute(input.merge("failure_code" => error.class.name.underscore))
  end
end
