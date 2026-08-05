require "rails_helper"

RSpec.describe ModelGateway do
  let(:result) { ModelResult.new(text: "Revenue grew.", model: "test-model", usage: {}) }
  let(:adapter) { instance_double(Models::GeminiAdapter, generate: result) }
  subject(:gateway) { described_class.new(adapter: adapter) }

  it "delegates a bounded prompt with its purpose" do
    expect(gateway.generate(prompt: "Explain revenue", purpose: "metric_explanation")).to eq(result)
    expect(adapter).to have_received(:generate).with(prompt: "Explain revenue", purpose: "metric_explanation")
  end

  it "rejects empty prompts before calling a provider" do
    expect { gateway.generate(prompt: "", purpose: "test") }.to raise_error(ArgumentError, /empty/)
    expect(adapter).not_to have_received(:generate)
  end

  it "rejects oversized prompts before calling a provider" do
    expect { gateway.generate(prompt: "x" * 16_001, purpose: "test") }.to raise_error(ArgumentError, /large/)
    expect(adapter).not_to have_received(:generate)
  end

  it "owns the task version, tool policy, structured output, and normalized usage" do
    structured = ModelResult.new(text: '{"explanations":[{"metric":"revenue","explanation":"Revenue grew."}]}',
      model: "test-model", usage: { "promptTokenCount" => 12, "candidatesTokenCount" => 8 })
    captured_prompt = nil
    allow(adapter).to receive(:generate) { |prompt:, **| captured_prompt = prompt; structured }
    execution = gateway.execute(task: "metric_explanations", input: { symbol: "AAPL", metrics: [ "revenue" ] })
    prompt = JSON.parse(captured_prompt)
    expect(prompt).to include("task" => "metric_explanations", "prompt_version" => "v1", "allowed_tools" => [ "fundamentals" ])
    expect(execution.to_h).to include(model: "test-model", usage: { input_tokens: 12, output_tokens: 8 }, prompt_version: "v1")
  end

  it "rejects provider JSON that does not match the task schema" do
    allow(adapter).to receive(:generate).and_return(ModelResult.new(text: '{"explanations":[]}', model: "test", usage: {}))
    expect { gateway.execute(task: "metric_explanations", input: { symbol: "AAPL", metrics: [ "revenue" ] }) }
      .to raise_error(ModelGateway::Error) { |error| expect(error.category).to eq(:invalid_response) }
  end

  it "classifies non-JSON provider output without returning it" do
    allow(adapter).to receive(:generate).and_return(ModelResult.new(text: "sensitive provider payload", model: "test", usage: {}))

    expect { gateway.execute(task: "financial_chat", input: { messages: [ { role: "user", content: "Hello" } ] }) }
      .to raise_error(ModelGateway::Error) { |error|
        expect(error.category).to eq(:invalid_response)
        expect(error.message).not_to include("sensitive")
      }
  end

  it "rejects malformed chat roles, content, and citations" do
    invalid = [
      { "message" => { "role" => "user", "content" => "Wrong role" } },
      { "message" => { "role" => "assistant", "content" => "" } },
      { "message" => { "role" => "assistant", "content" => "Answer" },
        "sources" => [ { "label" => "Source", "uri" => "file:///secret", "as_of" => "2026-08-05T12:00:00Z" } ] }
    ]

    invalid.each do |payload|
      allow(adapter).to receive(:generate).and_return(ModelResult.new(text: payload.to_json, model: "test", usage: {}))
      expect { gateway.execute(task: "financial_chat", input: { messages: [ { role: "user", content: "Hello" } ] }) }
        .to raise_error(ModelGateway::Error) { |error| expect(error.category).to eq(:invalid_response) }
    end
  end

  it "accepts the versioned explanation and chat golden fixtures" do
    explanation = ModelResult.new(text: file_fixture("model_explanations_golden.json").read, model: "fixture", usage: {})
    chat = ModelResult.new(text: file_fixture("model_chat_golden.json").read, model: "fixture", usage: {})
    allow(adapter).to receive(:generate).and_return(explanation, chat)
    expect(gateway.execute(task: "metric_explanations", input: { symbol: "AAPL", metrics: [ "revenue" ] }).prompt_version).to eq("v1")
    expect(gateway.execute(task: "financial_chat", input: { messages: [ { role: "user", content: "Revenue?" } ] }).payload)
      .to include("message" => include("role" => "assistant"))
  end

  it "rejects incomplete explanations and malformed citations" do
    excessive_sources = Array.new(21) do
      { "label" => "Source", "as_of" => "2026-01-01T00:00:00Z" }
    end
    invalid = [
      { "explanations" => [ { "metric" => "revenue", "explanation" => "One" },
        { "metric" => "revenue", "explanation" => "Two" } ] },
      { "explanations" => [ { "metric" => "revenue", "explanation" => "One",
        "sources" => [ { "label" => "Source", "uri" => "javascript:alert(1)", "as_of" => "2026-01-01T00:00:00Z" } ] } ] },
      { "explanations" => [ { "metric" => "revenue", "explanation" => "One",
        "sources" => excessive_sources } ] }
    ]
    invalid.each do |payload|
      allow(adapter).to receive(:generate).and_return(ModelResult.new(text: payload.to_json, model: "fixture", usage: {}))
      metrics = payload["explanations"].length == 2 ? %w[revenue earnings] : [ "revenue" ]
      expect { gateway.execute(task: "metric_explanations", input: { symbol: "AAPL", metrics: metrics }) }
        .to raise_error(ModelGateway::Error) { |error| expect(error.category).to eq(:invalid_response) }
    end
  end
end
