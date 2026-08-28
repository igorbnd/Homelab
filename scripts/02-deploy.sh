#!/usr/bin/env bash
# Renders manifests from .env and applies them.
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

RENDER_DIR="$REPO_ROOT/.rendered"
rm -rf "$RENDER_DIR"; mkdir -p "$RENDER_DIR"
cp "$REPO_ROOT"/manifests/*.yaml "$RENDER_DIR/"

info "Rendering with ORCA_LB_IP=$ORCA_LB_IP"
sed -i "s|metallb.universe.tf/loadBalancerIPs: .*|metallb.universe.tf/loadBalancerIPs: $ORCA_LB_IP|" "$RENDER_DIR/30-service.yaml"

info "Rendering with PROM_OTLP_ENDPOINT=$PROM_OTLP_ENDPOINT"
sed -i "s|endpoint: http://prometheus-operated.*|endpoint: $PROM_OTLP_ENDPOINT|" "$RENDER_DIR/10-configmap.yaml"

if [[ "$ORCA_NAMESPACE" != "orca" ]]; then
  info "Renaming namespace to $ORCA_NAMESPACE"
  sed -i "s|namespace: orca|namespace: $ORCA_NAMESPACE|g; s|name: orca$|name: $ORCA_NAMESPACE|" "$RENDER_DIR/00-namespace.yaml"
  sed -i "s|namespace: orca|namespace: $ORCA_NAMESPACE|g" "$RENDER_DIR"/{10,20,30}-*.yaml
fi

info "Pre-pulling the Orca image on eligible nodes (avoids a chicken-and-egg on restart)"
for node in $NODES; do
  ssh "$node" "sudo ctr -n k8s.io images pull -q docker.io/varnish/orca:latest" >/dev/null 2>&1 \
    && ok "pre-pulled on $node" || warn "pre-pull failed on $node (not fatal)"
done

info "Applying manifests"
kubectl apply -f "$RENDER_DIR/00-namespace.yaml"
kubectl apply -f "$RENDER_DIR/10-configmap.yaml"
kubectl apply -f "$RENDER_DIR/20-deployment.yaml"
kubectl apply -f "$RENDER_DIR/30-service.yaml"

info "Waiting for rollout"
kubectl -n "$ORCA_NAMESPACE" rollout status deploy/orca --timeout=180s

echo
kubectl -n "$ORCA_NAMESPACE" get pods,svc -o wide
echo
ok "Deployed. Next: add DNS or /etc/hosts entries, then run scripts/04-verify.sh."
