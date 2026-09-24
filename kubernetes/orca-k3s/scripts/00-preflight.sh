#!/usr/bin/env bash
# Discovers cluster facts and writes .env. Safe to re-run.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

info()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }

command -v kubectl >/dev/null || { echo "kubectl not found"; exit 1; }

info "Nodes and versions"
kubectl get nodes -o custom-columns=NAME:.metadata.name,VERSION:.status.nodeInfo.kubeletVersion,IP:.status.addresses[0].address,MEM:.status.capacity.memory

echo
info "Checking for k3s version skew"
SKEW=$(kubectl get nodes -o jsonpath='{range .items[*]}{.status.nodeInfo.kubeletVersion}{"\n"}{end}' | sort -u | wc -l)
if [[ "$SKEW" -gt 1 ]]; then
  warn "Multiple kubelet versions present. An agent NEWER than the server is unsupported."
  warn "Not blocking -- the manifests keep Orca off the mismatched node."
fi

echo
info "MetalLB address pools"
kubectl get ipaddresspool -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,ADDRESSES:.spec.addresses 2>/dev/null \
  || warn "No IPAddressPool CRDs found. Is MetalLB installed?"

echo
info "LoadBalancer addresses already in use"
kubectl get svc -A -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace}/{.metadata.name}{"\t"}{.status.loadBalancer.ingress[0].ip}{"\n"}{end}' 2>/dev/null || true

echo
info "Candidate Prometheus services"
kubectl get svc -A 2>/dev/null | grep -Ei 'prometheus|thanos' || warn "No Prometheus service found by name."

echo
if [[ -f .env ]]; then
  warn ".env already exists -- leaving it alone."
else
  cp .env.example .env
  info "Created .env from template."
fi

cat <<'MSG'

Now edit .env and set, at minimum:
  ORCA_LB_IP           a free address inside your MetalLB pool (see above)
  PROM_OTLP_ENDPOINT   http://<prom-svc>.<ns>.svc.cluster.local:9090/api/v1/otlp/v1/metrics
  PROM_QUERY_URL       http://<prom-svc>.<ns>.svc.cluster.local:9090

Then run scripts/01-baseline.sh BEFORE deploying anything.
MSG
