class ModelGateway
  class Error < StandardError
    attr_reader :category

    def initialize(category = :invalid_response, message = "model request failed")
      @category = category
      super(message)
    end
  end

  ALLOWED_TOOLS = %w[fundamentals portfolio].freeze
  TASKS = {
    "metric_explanations" => { prompt_version: "v1", tools: %w[fundamentals] },
    "financial_chat" => { prompt_version: "v1", tools: %w[fundamentals portfolio] },
    "research_report" => { prompt_version: "v1", tools: %w[fundamentals portfolio] }
  }.freeze

  def self.default
    @default ||= new(adapter: Models::GeminiAdapter.from_env)
  end

  def initialize(adapter:) = @adapter = adapter

  def generate(prompt:, purpose:)
    raise ArgumentError, "prompt is empty" if prompt.blank?
    raise ArgumentError, "prompt is too large" if prompt.bytesize > 16_000

    @adapter.generate(prompt: prompt, purpose: purpose)
  end

  def execute(task:, input:)
    definition = TASKS.fetch(task) { raise ArgumentError, "unknown model task" }
    raise Error.new(:policy_violation, "task requests a disallowed tool") unless (definition[:tools] - ALLOWED_TOOLS).empty?

    prompt = { task: task, prompt_version: definition[:prompt_version], allowed_tools: definition[:tools], input: input }.to_json
    result = generate(prompt: prompt, purpose: task)
    payload = JSON.parse(result.text)
    validate_payload!(task, payload, input)
    usage = { input_tokens: result.usage.fetch("promptTokenCount", 0).to_i,
      output_tokens: result.usage.fetch("candidatesTokenCount", 0).to_i }
    ModelExecution.new(payload: payload, model: result.model, usage: usage, task: task,
      prompt_version: definition[:prompt_version])
  rescue JSON::ParserError
    raise Error.new(:invalid_response, "model response is not valid JSON")
  end

  private

  def validate_payload!(task, payload, input)
    valid = case task
    when "metric_explanations"
      explanations = payload["explanations"]
      payload.keys == [ "explanations" ] && explanations.is_a?(Array) && explanations.length == input.fetch(:metrics).length &&
        explanations.all? do |item|
          item.is_a?(Hash) && (item.keys - %w[metric explanation sources]).empty? &&
            item["metric"].in?(input.fetch(:metrics)) && item["explanation"].to_s.length.between?(1, 5_000) && valid_sources?(item["sources"])
        end && explanations.pluck("metric").sort == input.fetch(:metrics).sort
    when "financial_chat"
      message = payload["message"]
      (payload.keys - %w[message sources]).empty? && message.is_a?(Hash) && message.keys.sort == %w[content role] &&
        message["role"] == "assistant" && message["content"].to_s.length.between?(1, 10_000) && valid_sources?(payload["sources"])
    when "research_report"
      valid_report_payload?(payload, input)
    end
    raise Error.new(:invalid_response, "model response does not match the task schema") unless valid
  end

  def valid_report_payload?(payload, input)
    return false unless payload.keys.sort == %w[claims content summary]
    return false unless payload["summary"].is_a?(String) && payload["summary"].length.between?(1, 10_000)
    return false unless payload["content"].is_a?(String) && payload["content"].length.between?(1, 200_000)

    allowed = input.fetch(:evidence).to_h { |source| [ source.fetch("source_id"), source.fetch("as_of") ] }
    claims = payload["claims"]
    claims.is_a?(Array) && claims.length.between?(1, 50) && claims.all? do |claim|
      claim.is_a?(Hash) && claim.keys.sort == %w[as_of sources text] && claim["text"].is_a?(String) &&
        claim["text"].length.between?(1, 5_000) && claim["sources"].is_a?(Array) &&
        claim["sources"].length.between?(1, 10) && claim["sources"].uniq == claim["sources"] &&
        claim["sources"].all? { |source_id| allowed.key?(source_id) } &&
        claim["sources"].any? { |source_id| allowed.fetch(source_id) == claim["as_of"] }
    end
  end

  def valid_sources?(sources)
    return true if sources.nil?
    sources.is_a?(Array) && sources.length <= 20 && sources.all? do |source|
      source.is_a?(Hash) && (source.keys - %w[label uri as_of]).empty? && source["label"].to_s.length.between?(1, 200) &&
        valid_source_uri?(source["uri"]) && Time.iso8601(source["as_of"].to_s)
    rescue ArgumentError
      false
    end
  end

  def valid_source_uri?(value)
    return true if value.nil?
    uri = URI.parse(value.to_s)
    uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    false
  end
end
