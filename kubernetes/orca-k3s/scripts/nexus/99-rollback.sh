#!/usr/bin/env bash
# Removes Nexus. Nothing here touches containerd/registries.yaml or restarts k3s --
# Nexus was never wired into it (direct-pull only, see CLAUDE.md "Comparison scope").
source "$(dirname "${BASH_SOURCE[0]}")/../_lib.sh"

read -r -p "Delete the nexus namespace? [y/N] " reply
[[ "$reply" =~ ^[Yy]$ ]] || fail "Aborted."

kubectl delete namespace nexus --ignore-not-found
ok "Rolled back."
