#!/usr/bin/env bash
# Proves Orca keeps serving when the upstream registry is unreachable.
# The most memorable of the demos.
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

# Bare `ctr images pull` ignores k3s's mirror config entirely -- only kubelet/CRI
# honours it automatically. Without --hosts-dir this demo would just try
# docker.io directly and correctly fail during the "outage", proving nothing
# about Orca. Same root cause as the benchmark script bug -- see
# results/notes.md 2026-09-24. --sync on rm avoids a false "still cached
# locally" result from containerd's content-store dedup (also 2026-09-24).
CTR_HOSTS_DIR="/var/lib/rancher/k3s/agent/etc/containerd/certs.d"

TARGET="${1:-}"
[[ -n "$TARGET" ]] || fail "Usage: $0 <node-ip>   (a node that will pull during the outage)"

cat <<'MSG'
This demo does the following:
  1. Warms the cache by pulling the benchmark image
  2. Asks you to block outbound access to the upstream registry
  3. Pulls again on a node with no local copy -- it should still succeed

Blocking is left manual because how you do it depends on your firewall.
On the Orca node you can simulate it with:
  sudo iptables -I OUTPUT -d registry-1.docker.io -j REJECT
and undo it with:
  sudo iptables -D OUTPUT -d registry-1.docker.io -j REJECT
MSG
echo

info "Warming the cache"
ssh "$TARGET" "sudo ctr -n k8s.io images rm --sync $BENCH_IMAGE >/dev/null 2>&1 || true"
ssh "$TARGET" "sudo ctr -n k8s.io images pull --hosts-dir $CTR_HOSTS_DIR $BENCH_IMAGE >/dev/null"
ok "Cache warm"

echo
read -r -p "Now block upstream access, then press Enter to continue... " _

info "Removing the local copy on $TARGET"
ssh "$TARGET" "sudo ctr -n k8s.io images rm --sync $BENCH_IMAGE >/dev/null 2>&1 || true"

info "Pulling during the simulated outage"
if ssh "$TARGET" "TIMEFORMAT='real %3R'; time sudo ctr -n k8s.io images pull --hosts-dir $CTR_HOSTS_DIR $BENCH_IMAGE >/dev/null"; then
  ok "Pull succeeded with the origin unreachable -- served entirely from Orca."
else
  warn "Pull failed. Check whether the mirror fell back to upstream, or whether the block was too broad."
fi

echo
read -r -p "Unblock upstream access, then press Enter to finish... " _
ok "Demo complete."
