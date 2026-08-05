module V1
  class ChatController < ApplicationController
    def create
      attributes = contract_params(:conversation_id, :symbol, :portfolio_id, :messages, required: [ :messages ])
      messages = Array(attributes[:messages]).map(&:to_h)
      unless messages.length.between?(1, 40) && messages.all? { |message| valid_message?(message) }
        raise ActionController::BadRequest, "messages do not match the chat contract"
      end
      policy_scope(Portfolio).find(attributes[:portfolio_id]) if attributes[:portfolio_id].present?
      conversation_id = attributes[:conversation_id].presence || SecureRandom.uuid
      AiUsageLimiter.new(user: Current.user, operation: "chat").consume!
      execution = ModelGateway.default.execute(task: "financial_chat",
        input: { messages: messages, symbol: attributes[:symbol], portfolio_id: attributes[:portfolio_id] })
      render json: { conversation_id: conversation_id, message: execution.payload.fetch("message"),
        sources: execution.payload.fetch("sources", []), usage: execution.usage }
    end

    private

    def valid_message?(message)
      %w[user assistant].include?(message["role"]) && message["content"].is_a?(String) &&
        message["content"].length.between?(1, 10_000) && (message.keys - %w[role content]).empty?
    end
  end
end
