module Reports
  class EventHandler
    def self.call(payload)
      return unless payload.fetch("status") == "queued"

      report = Report.find(payload.fetch("report_id"))
      raise ArgumentError, "report tenant does not match event" unless report.user_id.to_s == payload.dig("envelope", "tenant_id").to_s
      return unless report.status == "queued"

      workflow_id = payload.fetch("workflow_id")
      raise ArgumentError, "report workflow does not match event" unless workflow_id == "report-#{report.id}"
      raise ArgumentError, "report workflow changed" if report.workflow_id.present? && report.workflow_id != workflow_id
      report.update!(workflow_id: workflow_id) if report.workflow_id.nil?
      enqueued = ResearchReportJob.perform_later({ "report_id" => report.id, "workflow_id" => workflow_id,
        "correlation_id" => payload.dig("envelope", "correlation_id"), "focus" => payload["focus"] })
      raise "report job was not enqueued" if enqueued == false
    end
  end
end
