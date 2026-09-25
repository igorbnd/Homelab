#!/usr/bin/env bash
# Renders manifests from .env and applies them.
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

RENDER_DIR="$REPO_ROOT/.rendered"
rm -rf "$RENDER_DIR"; mkdir -p "$RENDER_DIR"
cp "$REPO_ROOT"/manifests/*.yaml "$RENDER_DIR/"

info "Rendering with PROM_OTLP_ENDPOINT=$PROM_OTLP_ENDPOINT"
sed -i.bak "s|endpoint: http://prometheus-operated.*|endpoint: $PROM_OTLP_ENDPOINT|" "$RENDER_DIR/10-configmap.yaml"

if [[ "$ORCA_NAMESPACE" != "orca" ]]; then
  info "Renaming namespace to $ORCA_NAMESPACE"
  sed -i.bak "s|namespace: orca|namespace: $ORCA_NAMESPACE|g; s|name: orca$|name: $ORCA_NAMESPACE|" "$RENDER_DIR/00-namespace.yaml"
  sed -i.bak "s|namespace: orca|namespace: $ORCA_NAMESPACE|g" "$RENDER_DIR"/{10,20,25,30}-*.yaml
fi
rm -f "$RENDER_DIR"/*.bak

info "Pre-pulling the Orca image on eligible nodes (avoids a chicken-and-egg on restart)"
for node in $NODES; do
  ssh "$node" "sudo ctr -n k8s.io images pull docker.io/varnish/orca:latest >/dev/null" >/dev/null 2>&1 \
    && ok "pre-pulled on $node" || warn "pre-pull failed on $node (not fatal)"
done

info "Applying namespace + license Secret"
kubectl apply -f "$RENDER_DIR/00-namespace.yaml"
if ! kubectl -n "$ORCA_NAMESPACE" get secret orca-license >/dev/null 2>&1; then
  LICENSE_FILE="${ORCA_LICENSE_FILE:-$REPO_ROOT/license.lic}"
  [[ -f "$LICENSE_FILE" ]] || fail "No license file at $LICENSE_FILE (set ORCA_LICENSE_FILE)."
  kubectl -n "$ORCA_NAMESPACE" create secret generic orca-license --from-file="license.lic=$LICENSE_FILE"
  ok "created orca-license Secret from $LICENSE_FILE"
else
  ok "orca-license Secret already exists, leaving it alone"
fi

if ! kubectl -n "$ORCA_NAMESPACE" get secret orca-cluster-token >/dev/null 2>&1; then
  # Not git-tracked, not owned by ArgoCD -- same out-of-band pattern as
  # orca-license. cluster.token has no file/env-ref alternative, so this gets
  # merged in via Orca's colon-separated --config flag instead.
  CLUSTER_TOKEN="${CLUSTER_TOKEN:-$(openssl rand -hex 24)}"
  kubectl -n "$ORCA_NAMESPACE" create secret generic orca-cluster-token \
    --from-literal="cluster-secret.yaml=cluster:
  token: $CLUSTER_TOKEN"
  ok "created orca-cluster-token Secret"
else
  ok "orca-cluster-token Secret already exists, leaving it alone"
fi

info "Applying config, cluster networking, and the StatefulSet"
kubectl apply -f "$RENDER_DIR/10-configmap.yaml"
kubectl apply -f "$RENDER_DIR/15-firewall-rulesets.yaml"
kubectl apply -f "$RENDER_DIR/25-headless-service.yaml"
kubectl apply -f "$RENDER_DIR/20-statefulset.yaml"
kubectl apply -f "$RENDER_DIR/30-service.yaml"

info "Pinning the LB IP (kept out of the tracked manifest -- ArgoCD would fight it, see results/notes.md)"
kubectl -n "$ORCA_NAMESPACE" annotate svc orca "metallb.universe.tf/loadBalancerIPs=$ORCA_LB_IP" --overwrite

info "Waiting for rollout (StatefulSet rolls pods one at a time)"
kubectl -n "$ORCA_NAMESPACE" rollout status statefulset/orca --timeout=300s

echo
kubectl -n "$ORCA_NAMESPACE" get pods,svc,pvc -o wide
echo
ok "Deployed. Next: add DNS or /etc/hosts entries, then run scripts/04-verify.sh."
