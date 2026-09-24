#!/usr/bin/env bash
# The headline demo: one origin fetch serves every node.
#
# IMPORTANT: `ctr images pull` is a low-level debug tool that does NOT read
# k3s's generated hosts.toml (the actual mirror config) unless told to via
# --hosts-dir -- confirmed 2026-09-24 by timestamp: a bare `ctr pull` produced
# zero Orca log/metric activity despite a real, measurable network fetch. Only
# real kubelet/CRI-driven pod pulls honour the mirror automatically. Without
# --hosts-dir below, this script silently measures raw internet speed with
# Orca fully bypassed -- see results/notes.md 2026-09-24.
#
# Also: this cluster's ctr build has no `-q` flag (removed/renamed in this
# containerd version -- errors "flag provided but not defined: -q"). Redirect
# stdout instead of relying on a quiet flag that may not exist.
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
info "blobs behind if another tag shares them, producing a false 'warm' number --"
info "see results/notes.md 2026-09-24)"
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
