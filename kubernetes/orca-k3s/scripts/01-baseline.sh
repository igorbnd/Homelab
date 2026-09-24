#!/usr/bin/env bash
# Captures cold-pull timings with NO caching in place.
# This is your control group -- you cannot recreate it after deploying Orca.
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
OUT="$RESULTS_DIR/baseline-$STAMP.txt"

warn "This must run BEFORE the registry mirror is configured."
read -r -p "Has registries.yaml NOT yet been installed? [y/N] " reply
[[ "$reply" =~ ^[Yy]$ ]] || fail "Aborting. Run this before 03-configure-nodes.sh."

{
  echo "Orca baseline (no cache) -- $STAMP"
  echo "Image: $BENCH_IMAGE"
  echo
} | tee "$OUT"

for node in $NODES; do
  info "Baseline pull on $node"
  {
    echo "--- $node ---"
    ssh "$node" "sudo ctr -n k8s.io images rm $BENCH_IMAGE >/dev/null 2>&1 || true"
    ssh "$node" "TIMEFORMAT='real %3R'; time sudo ctr -n k8s.io images pull -q $BENCH_IMAGE" 2>&1
    echo
  } | tee -a "$OUT"
done

ok "Baseline written to $OUT"
