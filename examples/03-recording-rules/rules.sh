#!/usr/bin/env bash
# README 3.9: the dashboards read recording rules, so the rules get the same
# treatment as code: syntax check, unit tests, and a contract check that every
# recorded series a dashboard queries is actually produced by a rule.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
# shellcheck source=../lib/assert.sh
source "$here/../lib/assert.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

promtool check config "$root/prometheus/prometheus.yml" > "$work/config.txt" 2>&1 || true
assert_match 'SUCCESS: .*prometheus.yml is valid' "$(cat "$work/config.txt")" "prometheus.yml is valid"

promtool check rules "$root"/prometheus/rules/*.yml > "$work/rules.txt" 2>&1 || true
assert_match 'SUCCESS: [0-9]+ rules found' "$(cat "$work/rules.txt")" "rule files parse"

promtool test rules "$root/prometheus/tests/red.rules.test.yml" > "$work/test.txt" 2>&1 || true
assert_match 'SUCCESS' "$(cat "$work/test.txt")" "recording rule unit tests pass"
if ! grep -q SUCCESS "$work/test.txt"; then cat "$work/test.txt"; fi

# Contract: recorded series used in dashboards (level:metric:operation names)
# must be defined by a rule.
yq '.groups[].rules[].record' "$root"/prometheus/rules/*.yml | sort -u > "$work/defined.txt"
find "$root/grafana/dashboards" -name '*.json' -exec jq -r '.. | objects | .expr? // empty' {} + \
  | grep -oE '\b[a-z_]+:[a-z0-9_]+:[a-z0-9_]+\b' | sort -u > "$work/used.txt" || true
assert_match '^[1-9]' "$(wc -l < "$work/used.txt" | tr -d ' ')" "dashboards query recorded series"
assert_eq "" "$(comm -23 "$work/used.txt" "$work/defined.txt")" \
  "every recorded series a dashboard queries has a recording rule"

finish
