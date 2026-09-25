#!/usr/bin/env bash
# Lists the metric series Orca is actually exporting, so the Grafana panels
# can use real names rather than guessed ones.
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

info "Port-forwarding Prometheus"
PF_NS=$(kubectl get svc -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' | grep -i prometheus | head -1)
echo "Using: $PF_NS"
NS="${PF_NS%%/*}"; SVC="${PF_NS##*/}"

kubectl -n "$NS" port-forward "svc/$SVC" 19090:9090 >/dev/null 2>&1 &
PF_PID=$!
trap 'kill $PF_PID 2>/dev/null || true' EXIT
sleep 4

info "Series with service_name=orca"
curl -s 'http://127.0.0.1:19090/api/v1/label/__name__/values' \
  | tr ',' '\n' | grep -iE 'varnish|orca|supervisor|firewall|^"http_' | tr -d '"[]' | sort -u \
  | tee "$RESULTS_DIR/orca-metric-names.txt"

echo
ok "Metric names saved to results/orca-metric-names.txt"
echo "Diff against grafana/orca-dashboard.json's queries if re-verifying."
