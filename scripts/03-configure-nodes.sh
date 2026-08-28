#!/usr/bin/env bash
# Installs registries.yaml on every node and restarts k3s in the right order.
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

warn "This reconfigures containerd on ALL nodes and restarts k3s."
warn "Make sure scripts/01-baseline.sh has already been run."
read -r -p "Continue? [y/N] " reply
[[ "$reply" =~ ^[Yy]$ ]] || fail "Aborted."

RENDERED_REG=$(mktemp)
sed "s|orca\.lan|$ORCA_DOMAIN|g" "$REPO_ROOT/node/registries.yaml" > "$RENDERED_REG"

for node in $NODES; do
  info "Installing registries.yaml on $node"
  scp -q "$RENDERED_REG" "$node:/tmp/registries.yaml"
  ssh "$node" "sudo install -m 0644 /tmp/registries.yaml /etc/rancher/k3s/registries.yaml && rm /tmp/registries.yaml"
done
rm -f "$RENDERED_REG"

info "Restarting agents first, server last"
for node in $NODES; do
  if ssh "$node" "systemctl is-active --quiet k3s-agent" 2>/dev/null; then
    info "Restarting k3s-agent on $node"
    ssh "$node" "sudo systemctl restart k3s-agent"
    sleep 5
  fi
done

for node in $NODES; do
  if ssh "$node" "systemctl is-active --quiet k3s" 2>/dev/null; then
    info "Restarting k3s server on $node"
    ssh "$node" "sudo systemctl restart k3s"
  fi
done

info "Waiting for nodes to settle"
sleep 20
kubectl get nodes
kubectl -n "$ORCA_NAMESPACE" get pods
ok "Done. Run scripts/04-verify.sh."
