#!/usr/bin/env bash
# Live smoke test against a running stack (compose or the CI docker job).
#   GRAFANA_PASSWORD=... bash examples/live/smoke.sh
# It checks what a user would notice first: Grafana is up, provisioning ran,
# and a panel query actually reaches Prometheus through Grafana.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib/assert.sh
source "$here/../lib/assert.sh"

url="${GRAFANA_URL:-http://localhost:3000}"
user="${GRAFANA_USER:-admin}"
: "${GRAFANA_PASSWORD:?set GRAFANA_PASSWORD to the admin password the stack was started with}"

api() { curl -fsS -u "$user:$GRAFANA_PASSWORD" -H 'Content-Type: application/json' "$@"; }

# 1. Health: database reachable and the expected major version.
health="$(curl -fsS "$url/api/health")"
assert_eq "ok" "$(jq -r '.database' <<< "$health")" "/api/health reports the database as ok"
assert_match '^1[3-9]\.' "$(jq -r '.version' <<< "$health")" "Grafana major version is 13 or newer"

# 2. Data sources were provisioned with the uids dashboards depend on.
assert_eq "prometheus" "$(api "$url/api/datasources/uid/prometheus" | jq -r '.type')" "Prometheus data source exists"
assert_eq "grafana-testdata-datasource" "$(api "$url/api/datasources/uid/testdata" | jq -r '.type')" "TestData data source exists"

# 3. Dashboards were provisioned into folders and are marked as provisioned.
red="$(api "$url/api/dashboards/uid/learn-grafana-red")"
assert_eq "true" "$(jq -r '.meta.provisioned' <<< "$red")" "RED dashboard is provisioned"
assert_eq "platform" "$(jq -r '.meta.folderTitle' <<< "$red")" "RED dashboard sits in the platform folder"
assert_eq "sandbox" "$(api "$url/api/dashboards/uid/learn-grafana-transforms" | jq -r '.meta.folderTitle')" \
  "playground dashboard sits in the sandbox folder"

# 4. A query travels browser-style through /api/ds/query to Prometheus.
#    Retry: Prometheus needs a scrape or two (and a rule evaluation) first.
query() {
  api -X POST "$url/api/ds/query" -d "{
    \"from\": \"now-5m\", \"to\": \"now\",
    \"queries\": [{\"refId\": \"A\", \"datasource\": {\"uid\": \"prometheus\"},
                   \"expr\": \"$1\", \"instant\": true, \"range\": false}]
  }"
}
frames=0
for _ in $(seq 1 30); do
  frames="$(query 'up{job=\"grafana\"}' | jq '.results.A.frames | length')"
  [[ "$frames" -ge 1 ]] && break
  sleep 3
done
assert_match '^[1-9]' "$frames" "up{job=\"grafana\"} returns data through Grafana"

recorded=0
for _ in $(seq 1 40); do
  recorded="$(query 'job:http_requests:rate5m' | jq '[.results.A.frames[]?] | length')"
  [[ "$recorded" -ge 1 ]] && break
  sleep 3
done
assert_match '^[1-9]' "$recorded" "the recording rule job:http_requests:rate5m has data"

finish
