class AiUsageLimiter
  LimitExceeded = Class.new(StandardError)

  def initialize(user:, operation:, now: Time.current, limit: ENV.fetch("AI_REQUESTS_PER_HOUR", 30).to_i)
    @user = user
    @operation = operation
    @window = now.beginning_of_hour
    @limit = limit
  end

  def consume!
    AiUsageWindow.transaction do
      usage = AiUsageWindow.lock.find_or_create_by!(user: @user, operation: @operation, window_started_at: @window)
      raise LimitExceeded, "AI request quota exceeded" if usage.request_count >= @limit

      usage.increment!(:request_count)
    end
  rescue ActiveRecord::RecordNotUnique
    retry
  end
end
