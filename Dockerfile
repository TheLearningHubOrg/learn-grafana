# Grafana with this repo's configuration, data sources and dashboards baked in.
#   docker build -t learn-grafana .
#   docker run --rm -p 3000:3000 -e GF_SECURITY_ADMIN_PASSWORD=... learn-grafana
# The validate stage runs examples/run-all.sh, so an image is only produced
# when every dashboard lints clean and the recording-rule tests pass.

# ---- promtool: borrow the static binary from the official Prometheus image ---
FROM prom/prometheus:v3.15.1 AS promtool

# ---- lint: fail the build on ShellCheck warnings in the example scripts ------
FROM koalaman/shellcheck-alpine:stable AS lint
WORKDIR /src
COPY examples ./examples
RUN find examples -name '*.sh' -print0 | xargs -0 -r shellcheck -x --severity=warning

# ---- validate: dashboard lint, provisioning checks, promtool unit tests ------
FROM alpine:3.22 AS validate
RUN apk add --no-cache bash coreutils findutils grep gawk jq yq-go
COPY --from=promtool /bin/promtool /usr/local/bin/promtool
WORKDIR /src
COPY compose.yaml ./
COPY prometheus ./prometheus
COPY grafana ./grafana
COPY --from=lint /src/examples ./examples
RUN bash examples/run-all.sh

# ---- runtime: the official image already runs as the non-root grafana user ---
FROM grafana/grafana:13.3.0 AS runtime
COPY --from=validate --chown=472:0 /src/grafana/grafana.ini /etc/grafana/grafana.ini
COPY --from=validate --chown=472:0 /src/grafana/provisioning /etc/grafana/provisioning
COPY --from=validate --chown=472:0 /src/grafana/dashboards /etc/grafana/dashboards
USER 472
EXPOSE 3000
HEALTHCHECK --interval=15s --timeout=5s --start-period=30s --retries=3 \
  CMD wget -qO- http://127.0.0.1:3000/api/health >/dev/null || exit 1
