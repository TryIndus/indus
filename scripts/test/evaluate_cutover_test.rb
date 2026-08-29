# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "open3"
require "tempfile"

class EvaluateCutoverTest < Minitest::Test
  SCRIPT = File.expand_path("../evaluate-cutover.sh", __dir__)
  HEALTHY = {
    "window_minutes" => 10,
    "error_rate" => 0.02,
    "p95_latency_ms" => 500,
    "reconciliation_mismatches" => 0,
    "stream_delay_seconds" => 5,
    "workflow_terminal_rate" => 0.99
  }.freeze

  {
    "error rate" => [ "error_rate", 0.020001, "error_rate>2%" ],
    "latency" => [ "p95_latency_ms", 501, "p95_latency>500ms" ],
    "reconciliation" => [ "reconciliation_mismatches", 1, "data_reconciliation_mismatch" ],
    "stream delay" => [ "stream_delay_seconds", 5.1, "stream_delay>5s" ],
    "workflow completion" => [ "workflow_terminal_rate", 0.989, "workflow_terminal_rate<99%" ]
  }.each do |name, (metric, value, reason)|
    define_method("test_#{name.tr(" ", "_")}_crossing_aborts_cutover") do
      stdout, stderr, status = run_metrics(HEALTHY.merge(metric => value))

      assert_equal 10, status.exitstatus, stderr
      assert_equal "ROLLBACK #{reason}\n", stdout
    end
  end

  def test_exact_abort_thresholds_continue
    stdout, stderr, status = run_metrics(HEALTHY)

    assert status.success?, stderr
    assert_equal "CONTINUE all cutover abort thresholds are within bounds\n", stdout
  end

  def test_all_abort_reasons_are_reported_together
    unhealthy = HEALTHY.merge(
      "error_rate" => 0.5,
      "p95_latency_ms" => 900,
      "reconciliation_mismatches" => 2,
      "stream_delay_seconds" => 30,
      "workflow_terminal_rate" => 0.5
    )

    stdout, stderr, status = run_metrics(unhealthy)

    assert_equal 10, status.exitstatus, stderr
    assert_equal(
      "ROLLBACK error_rate>2%,p95_latency>500ms,data_reconciliation_mismatch,stream_delay>5s,workflow_terminal_rate<99%\n",
      stdout
    )
  end

  def test_malformed_or_unsafe_observations_are_rejected
    invalid_observations = [
      HEALTHY.merge("window_minutes" => 9.99),
      HEALTHY.merge("error_rate" => -0.1),
      HEALTHY.merge("p95_latency_ms" => "fast"),
      HEALTHY.merge("reconciliation_mismatches" => -1),
      HEALTHY.merge("stream_delay_seconds" => nil),
      HEALTHY.merge("workflow_terminal_rate" => 1.01),
      HEALTHY.reject { |key, _value| key == "error_rate" }
    ]

    invalid_observations.each do |observation|
      stdout, stderr, status = run_metrics(observation)

      assert_equal 2, status.exitstatus, "accepted #{observation.inspect}"
      assert_empty stdout
      assert_includes stderr, "Malformed or too-short observation window."
    end
  end

  def test_missing_metrics_file_is_rejected
    stdout, stderr, status = Open3.capture3(SCRIPT, "/tmp/indus-missing-cutover-metrics.json")

    assert_equal 2, status.exitstatus
    assert_empty stdout
    assert_includes stderr, "Usage:"
  end

  private

  def run_metrics(metrics)
    Tempfile.create([ "cutover-metrics", ".json" ]) do |file|
      file.write(JSON.generate(metrics))
      file.flush
      return Open3.capture3(SCRIPT, file.path)
    end
  end
end
