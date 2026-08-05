module Reports
  class ActivityExecution
    InProgress = Class.new(StandardError)

    def self.run(report_id:, activity_key:)
      execution = claim(report_id:, activity_key:)
      return execution.result if execution.status == "completed"

      result = yield
      execution.with_lock do
        execution.update!(status: "completed", result: result || {}, last_error: nil)
      end
      result
    rescue StandardError => error
      execution&.update!(status: "failed", last_error: error.class.name.to_s.byteslice(0, 120))
      raise
    end

    def self.claim(report_id:, activity_key:)
      Report.transaction do
        report = Report.lock.find(report_id)
        raise ReportCancelled, "report was cancelled" if report.status == "cancelled"

        execution = ReportActivityExecution.find_or_initialize_by(report: report, activity_key: activity_key)
        execution.lock! if execution.persisted?
        return execution if execution.status == "completed"

        execution.assign_attributes(status: "running", attempts: execution.attempts + 1, last_error: nil)
        execution.save!
        execution
      end
    rescue ActiveRecord::RecordNotUnique
      retry
    end

    private_class_method :claim
  end

  class ReportCancelled < StandardError; end
end
