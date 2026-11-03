#!/usr/bin/env bash
# README 1.5-1.7: cross-file checks that Grafana itself only reports at
# startup (or never). Each assertion names the mistake it prevents.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
# shellcheck source=../lib/assert.sh
source "$here/../lib/assert.sh"

ds="$root/grafana/provisioning/datasources/datasources.yaml"
dp="$root/grafana/provisioning/dashboards/dashboards.yaml"
ini="$root/grafana/grafana.ini"
compose="$root/compose.yaml"
prom="$root/prometheus/prometheus.yml"

# --- data sources -------------------------------------------------------------
assert_eq "1" "$(yq '.apiVersion' "$ds")" "datasources.yaml uses apiVersion 1"
assert_eq "0" "$(yq '[.datasources[] | select(has("uid") | not)] | length' "$ds")" \
  "every data source pins a uid (dashboards reference uids, not names)"
assert_eq "" "$(yq '.datasources[].uid' "$ds" | sort | uniq -d)" "data source uids are unique"
assert_eq "" "$(yq '.datasources[].uid' "$ds" | grep -Ev '^[a-zA-Z0-9_-]{1,40}$' || true)" \
  "data source uids match the format Grafana 12+ enforces"
assert_eq "1" "$(yq '[.datasources[] | select(.isDefault == true)] | length' "$ds")" \
  "exactly one default data source"

# $__rate_interval is computed from the data source's scrape interval.
assert_eq "$(yq '.global.scrape_interval' "$prom")" \
  "$(yq '.datasources[] | select(.type == "prometheus") | .jsonData.timeInterval' "$ds")" \
  "Prometheus data source timeInterval equals the scrape_interval"

# The data source URL must use the compose service name, not localhost.
assert_match '^http://prometheus:9090$' "$(yq '.datasources[] | select(.uid == "prometheus") | .url' "$ds")" \
  "Prometheus URL targets the compose service"
assert_eq "prometheus" "$(yq '.services | keys | .[] | select(. == "prometheus")' "$compose")" \
  "compose.yaml defines the prometheus service the URL points at"

# --- dashboard provider -------------------------------------------------------
assert_eq "1" "$(yq '.apiVersion' "$dp")" "dashboards.yaml uses apiVersion 1"
path="$(yq '.providers[0].options.path' "$dp")"
assert_eq "/etc/grafana/dashboards" "$path" "provider reads /etc/grafana/dashboards"
assert_match "grafana/dashboards:${path}" "$(yq '.services.grafana.volumes[]' "$compose")" \
  "compose mounts the dashboards at the provider path"
assert_eq "true" "$(yq '.providers[0].options.foldersFromFilesStructure' "$dp")" \
  "sub-directories become folders"
assert_eq "null" "$(yq '.providers[0].folder' "$dp")" \
  "no fixed folder is set next to foldersFromFilesStructure (Grafana rejects both)"
assert_eq "false" "$(yq '.providers[0].allowUiUpdates' "$dp")" "UI saves cannot drift from Git"

# --- grafana.ini --------------------------------------------------------------
# Read one key from one [section] of an ini file.
ini_get() {
  awk -F' *= *' -v sect="[$1]" -v key="$2" '
    /^\[/ { in_sect = ($0 == sect) }
    in_sect && $1 == key { print $2; exit }' "$3"
}
assert_eq "Viewer" "$(ini_get auth.anonymous org_role "$ini")" "anonymous users are read-only"
assert_eq "false" "$(ini_get users allow_sign_up "$ini")" "self sign-up is off"
assert_eq "0.0.0.0" "$(ini_get server http_addr "$ini")" "Grafana binds all interfaces inside the container"
assert_eq "" "$(grep -E '^\s*admin_password\s*=' "$ini" || true)" "no admin password is committed"
assert_eq "$(ini_get dashboards default_home_dashboard_path "$ini")" \
  "$path/platform/service-overview.json" "home dashboard path points inside the provider path"
assert_eq "true" "$([[ -f "$root/grafana/dashboards/platform/service-overview.json" ]] && echo true || echo false)" \
  "home dashboard file exists in the repo"

finish
