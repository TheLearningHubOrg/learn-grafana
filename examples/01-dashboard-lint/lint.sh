#!/usr/bin/env bash
# README 2.1 and 3.10: lint every provisioned dashboard with rules.jq, then
# prove the linter catches mistakes by running it on a broken fixture.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
# shellcheck source=../lib/assert.sh
source "$here/../lib/assert.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# The uids that provisioning creates are the only ones a dashboard may use.
allowed="$(yq -o=json -I=0 '[.datasources[].uid]' "$root/grafana/provisioning/datasources/datasources.yaml")"
assert_match '"prometheus"' "$allowed" "provisioning defines the prometheus uid"
assert_match '"testdata"' "$allowed" "provisioning defines the testdata uid"

count=0
while IFS= read -r -d '' dash; do
  count=$((count + 1))
  name="${dash#"$root"/}"
  if ! jq empty "$dash" 2> "$work/err"; then
    assert_eq "valid JSON" "$(cat "$work/err")" "$name parses"
    continue
  fi
  violations="$(jq -r --argjson allowed "$allowed" -f "$here/rules.jq" "$dash")"
  assert_eq "" "$violations" "$name has no lint violations"
done < <(find "$root/grafana/dashboards" -name '*.json' -print0 | sort -z)
assert_match '^[1-9][0-9]*$' "$count" "found dashboards to lint ($count)"

# Dashboard uids must be unique across the whole provisioning tree.
dupes="$(find "$root/grafana/dashboards" -name '*.json' -exec jq -r '.uid' {} + | sort | uniq -d)"
assert_eq "" "$dupes" "dashboard uids are unique"

# The broken fixture must trip every rule it was written to trip.
jq -r --argjson allowed "$allowed" -f "$here/rules.jq" "$here/fixtures/broken-dashboard.json" > "$work/broken.txt"
broken="$(cat "$work/broken.txt")"
assert_match 'uid "this uid' "$broken" "rejects a uid with spaces"
assert_match 'id must be null' "$broken" "rejects a hard-coded dashboard id"
assert_match 'schemaVersion 27' "$broken" "rejects an old schemaVersion"
assert_match 'panel id 1 is used by 2 panels' "$broken" "rejects duplicate panel ids"
assert_match 'overflows the 24-column grid' "$broken" "rejects a panel wider than the grid"
assert_match 'unknown data source' "$broken" "rejects a data source uid that provisioning does not create"
assert_match 'should use \[\$__rate_interval\]' "$broken" "rejects rate() with a fixed window"
assert_match 'has no unit' "$broken" "rejects a time series panel without a unit"
assert_match 'no data source variable' "$broken" "rejects \${datasource} without the variable"
assert_eq "9" "$(wc -l < "$work/broken.txt" | tr -d ' ')" "fixture produces exactly 9 violations"

finish
