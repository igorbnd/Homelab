#!/usr/bin/env bash
# The headline demo: one origin fetch serves every node.
#
# `ctr images pull` doesn't read k3s's generated hosts.toml unless told to via
# --hosts-dir -- only kubelet/CRI-driven pod pulls honour the mirror
# automatically. Without --hosts-dir this silently measures raw internet
# speed with Orca fully bypassed.
#
# This cluster's ctr build also has no `-q` flag -- redirecting stdout instead.
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

CTR_HOSTS_DIR="/var/lib/rancher/k3s/agent/etc/containerd/certs.d"

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
OUT="$RESULTS_DIR/benchmark-$STAMP.txt"

{
  echo "Orca cold/warm benchmark -- $STAMP"
  echo "Image: $BENCH_IMAGE"
  echo
} | tee "$OUT"

info "Clearing the image from every node (--sync: a plain rm can leave content"
info "blobs behind if another tag shares them, producing a false 'warm' number)"
for node in $NODES; do
  ssh "$node" "sudo ctr -n k8s.io images rm --sync $BENCH_IMAGE >/dev/null 2>&1 || true"
done

FIRST=1
for node in $NODES; do
  if [[ "$FIRST" -eq 1 ]]; then
    LABEL="COLD (Orca fetches from origin)"; FIRST=0
  else
    LABEL="WARM (served from Orca cache)"
  fi
  info "$node -- $LABEL"
  {
    echo "--- $node : $LABEL ---"
    ssh "$node" "TIMEFORMAT='real %3R'; time sudo ctr -n k8s.io images pull --hosts-dir $CTR_HOSTS_DIR $BENCH_IMAGE >/dev/null" 2>&1
    echo
  } | tee -a "$OUT"
done

echo | tee -a "$OUT"
echo "Compare against results/baseline-*.txt for the no-cache control." | tee -a "$OUT"
ok "Written to $OUT"
