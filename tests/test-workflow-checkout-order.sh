#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "${ROOT_DIR}"

ruby <<'RUBY'
require "yaml"

workflow_paths = Dir.glob(".github/workflows/*.yml").sort
violations = []

def repo_script_step?(step)
  run = step["run"]
  return false unless run.is_a?(String)

  run.each_line.any? do |line|
    stripped = line.strip
    stripped.match?(%r{\A(?:bash|source)\s+scripts/}) ||
      stripped.match?(%r{\A\./scripts/}) ||
      stripped.match?(%r{\Ascripts/[^[:space:]]+}) ||
      stripped.match?(%r{\A(?:bash|source)\s+tests/[^[:space:]]+\.sh}) ||
      stripped.match?(%r{\Atests/[^[:space:]]+\.sh})
  end
end

def checkout_step?(step)
  uses = step["uses"]
  return false unless uses.is_a?(String)
  uses.start_with?("actions/checkout@")
end

workflow_paths.each do |path|
  data = YAML.load_file(path)
  jobs = data.fetch("jobs", {})
  jobs.each do |job_name, job|
    steps = job["steps"]
    next unless steps.is_a?(Array)

    checked_out = false
    steps.each do |step|
      checked_out ||= checkout_step?(step)
      next unless repo_script_step?(step)
      next if checked_out

      step_name = step["name"] || "(unnamed step)"
      violations << "#{path}: job=#{job_name} step=#{step_name}"
    end
  end
end

if violations.empty?
  puts "PASS [workflow-checkout-order]"
  exit 0
end

warn "FAIL: repo-owned scripts are invoked before checkout in:"
violations.each { |v| warn "  - #{v}" }
exit 1
RUBY
