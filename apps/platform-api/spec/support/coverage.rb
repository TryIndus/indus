return unless ENV["COVERAGE"] == "true"

require "coverage"

application_root = File.expand_path("../../app/", __dir__)
Coverage.start(lines: true, branches: true)

at_exit do
  result = Coverage.result.select { |path, _data| path.start_with?(application_root) }
  lines = result.values.flat_map { |data| data.fetch(:lines).compact }
  branches = result.values.flat_map do |data|
    data.fetch(:branches).values.flat_map(&:values)
  end

  line_coverage = lines.empty? ? 0.0 : lines.count(&:positive?) * 100.0 / lines.length
  branch_coverage = if branches.empty?
    0.0
  else
    branches.count(&:positive?) * 100.0 / branches.length
  end

  warn format("Rails coverage: %.2f%% lines, %.2f%% branches", line_coverage, branch_coverage)

  next if line_coverage >= 80.0 && branch_coverage >= 65.0

  warn "Rails coverage is below the required 80% line and 65% branch thresholds"
  exit 1
end
