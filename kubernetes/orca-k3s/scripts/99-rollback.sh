#!/usr/bin/env bash
# Removes the mirror config and Orca. Know this before you need it.
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

read -r -p "Remove registries.yaml from all nodes and delete Orca? [y/N] " reply
[[ "$reply" =~ ^[Yy]$ ]] || fail "Aborted."

for node in $NODES; do
  info "Removing registries.yaml on $node"
  ssh "$node" "sudo rm -f /etc/rancher/k3s/registries.yaml"
done

info "Restarting agents first"
for node in $NODES; do
  ssh "$node" "systemctl is-active --quiet k3s-agent" 2>/dev/null \
    && { ssh "$node" "sudo systemctl restart k3s-agent"; sleep 5; } || true
done

info "Restarting server"
for node in $NODES; do
  ssh "$node" "systemctl is-active --quiet k3s" 2>/dev/null \
    && ssh "$node" "sudo systemctl restart k3s" || true
done

info "Deleting the Orca namespace"
kubectl delete namespace "$ORCA_NAMESPACE" --ignore-not-found

sleep 15
kubectl get nodes
ok "Rolled back."
