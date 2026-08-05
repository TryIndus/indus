class AiUsageLimiter
  LimitExceeded = Class.new(StandardError)
  LIMITS = {
    "explanation" => { "hour" => 20, "day" => 100 },
    "chat" => { "hour" => 30, "day" => 150 },
    "report" => { "hour" => 5, "day" => 20 }
  }.freeze

  def initialize(user:, operation:, now: Time.current, limit: nil)
    @user = user
    @operation = operation
    @now = now
    @limits = limit ? { "hour" => limit, "day" => limit } : LIMITS.fetch(operation)
  end

  def consume!
    @user.with_lock do
      windows = @limits.map do |window_type, limit|
        started_at = window_type == "hour" ? @now.beginning_of_hour : @now.beginning_of_day
        usage = AiUsageWindow.lock.find_or_create_by!(user: @user, operation: @operation, window_type: window_type,
          window_started_at: started_at)
        raise LimitExceeded, "AI request quota exceeded" if usage.request_count >= limit
        usage
      end
      windows.each { |usage| usage.increment!(:request_count) }
    end
  rescue ActiveRecord::RecordNotUnique
    retry
  end
end
