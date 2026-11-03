# Dashboard lint rules. Input: one dashboard JSON (classic model).
# Arg: $allowed, the data source uids that provisioning creates.
# Output: one violation string per line; no output means the dashboard is clean.
#   jq -r --argjson allowed '["prometheus","testdata"]' -f rules.jq dash.json

# Every panel, including panels nested inside collapsed rows.
def all_panels: [.panels[]? | ., (.panels[]? // empty)];

# A reference is fine when it is the dashboard's data source variable,
# a built-in pseudo data source, or a uid that provisioning creates.
def ds_ok:
  . == null
  or (type == "string" and test("^\\$\\{?datasource\\}?$"))
  or (type == "object" and (
        (.uid // "") as $u
        | ($u | test("^\\$\\{?datasource\\}?$"))
          or ($u == "-- Grafana --" or $u == "-- Mixed --" or $u == "-- Dashboard --" or $u == "__expr__")
          or ($allowed | index($u)) != null));

def uses_ds_var: [.. | objects | .uid? // empty | strings | select(test("^\\$\\{?datasource\\}?$"))] | length > 0;

. as $d
| all_panels as $panels
| [
    (if (.uid // "") | test("^[a-zA-Z0-9_-]{1,40}$") | not
     then "uid \"\(.uid // "")\" must be 1-40 chars of [a-zA-Z0-9_-]" else empty end),

    (if .id != null then "id must be null in a provisioned dashboard (found \(.id))" else empty end),

    (if (.title // "") == "" then "dashboard title is empty" else empty end),

    (if (.schemaVersion // 0) < 39 then "schemaVersion \(.schemaVersion // 0) is older than 39; re-export from current Grafana" else empty end),

    ($panels | group_by(.id) | map(select(length > 1)) | .[]
      | "panel id \(.[0].id) is used by \(length) panels"),

    ($panels[] | select(.gridPos == null) | "panel \(.id) \"\(.title)\" has no gridPos"),

    ($panels[] | select(.gridPos != null and (.gridPos.x + .gridPos.w) > 24)
      | "panel \(.id) \"\(.title)\" overflows the 24-column grid (x=\(.gridPos.x), w=\(.gridPos.w))"),

    ($panels[] | select((.title // "") == "") | "panel \(.id) has no title"),

    ($panels[] | select(.datasource | ds_ok | not)
      | "panel \(.id) \"\(.title)\" uses unknown data source \(.datasource | tojson)"),

    ($panels[] | . as $p | .targets[]? | select(.datasource | ds_ok | not)
      | "panel \($p.id) query \(.refId) uses unknown data source \(.datasource | tojson)"),

    ($panels[] | . as $p | .targets[]? | select((.expr // "") | test("\\b(rate|irate|increase)\\("))
      | select((.expr) | test("\\$__rate_interval") | not)
      | "panel \($p.id) query \(.refId): rate()/increase() should use [$__rate_interval], not a fixed window"),

    ($panels[] | select(.type == "timeseries" or .type == "stat" or .type == "gauge" or .type == "bargauge")
      | select((.fieldConfig.defaults.unit // "") == "")
      | "panel \(.id) \"\(.title)\" (\(.type)) has no unit"),

    (if ($d | uses_ds_var) and ([$d.templating.list[]? | select(.name == "datasource" and .type == "datasource")] | length == 0)
     then "panels use ${datasource} but no data source variable named \"datasource\" exists" else empty end)
  ]
| .[]
