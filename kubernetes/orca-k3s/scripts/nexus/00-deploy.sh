#!/usr/bin/env bash
# Deploys Nexus Repository OSS3 for the JFrog/Nexus comparison track.
# Direct-pull only -- not wired into containerd/registries.yaml, see CLAUDE.md
# "Comparison scope".
source "$(dirname "${BASH_SOURCE[0]}")/../_lib.sh"

RENDER_DIR="$REPO_ROOT/.rendered-nexus"
rm -rf "$RENDER_DIR"; mkdir -p "$RENDER_DIR"
cp "$REPO_ROOT"/manifests/nexus/*.yaml "$RENDER_DIR/"

info "Rendering with NEXUS_LB_IP=$NEXUS_LB_IP"
sed -i.bak "s|metallb.universe.tf/loadBalancerIPs: .*|metallb.universe.tf/loadBalancerIPs: $NEXUS_LB_IP|" "$RENDER_DIR/30-service.yaml"
rm -f "$RENDER_DIR/30-service.yaml.bak"

info "Applying manifests"
kubectl apply -f "$RENDER_DIR/00-namespace.yaml"
kubectl apply -f "$RENDER_DIR/20-deployment.yaml"
kubectl apply -f "$RENDER_DIR/30-service.yaml"

info "Waiting for rollout (Nexus is slow to start, allow a few minutes)"
kubectl -n nexus rollout status deploy/nexus --timeout=300s

echo
kubectl -n nexus get pods,svc -o wide
echo
ok "Deployed. Next: scripts/nexus/01-configure-repos.sh"
