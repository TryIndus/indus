module V1
  class ReportsController < ApplicationController
    def index
      scope = policy_scope(Report)
      if params[:status].present?
        raise ActionController::BadRequest, "invalid report status" unless Report::STATUSES.include?(params[:status])
        scope = scope.where(status: params[:status])
      end
      result = page(scope)
      render json: { items: result[:records].map { |report| report_json(report) }, next_cursor: result[:next_cursor] }
    end

    def show
      report = policy_scope(Report).find(params[:id])
      authorize report
      render json: report_detail_json(report)
    end

    def create
      attributes = contract_params(:symbol, :portfolio_id, :focus, required: [ :symbol ])
      policy_scope(Portfolio).find(attributes[:portfolio_id]) if attributes[:portfolio_id].present?
      if attributes[:focus].present? && !attributes[:focus].length.between?(1, 1_000)
        raise ActionController::BadRequest, "focus must be between 1 and 1000 characters"
      end
      report = Current.user.reports.new(symbol: attributes[:symbol], portfolio_id: attributes[:portfolio_id],
        title: "#{attributes[:symbol].to_s.upcase} research report")
      authorize report
      Report.transaction do
        report.save!
        OutboxEvent.create!(topic: "report.requested", aggregate_type: "Report", aggregate_id: report.id,
          payload: { report_id: report.id, user_id: Current.user.id, symbol: report.symbol })
      end
      response.set_header("Location", "/v1/reports/#{report.id}")
      render json: report_json(report), status: :accepted
    end

    def destroy
      report = policy_scope(Report).find(params[:id])
      authorize report
      report.destroy!
      head :no_content
    end
  end
end
