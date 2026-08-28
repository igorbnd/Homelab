#!/usr/bin/env bash
# The headline demo: one origin fetch serves every node.
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
OUT="$RESULTS_DIR/benchmark-$STAMP.txt"

{
  echo "Orca cold/warm benchmark -- $STAMP"
  echo "Image: $BENCH_IMAGE"
  echo
} | tee "$OUT"

info "Clearing the image from every node"
for node in $NODES; do
  ssh "$node" "sudo ctr -n k8s.io images rm $BENCH_IMAGE >/dev/null 2>&1 || true"
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
    ssh "$node" "TIMEFORMAT='real %3R'; time sudo ctr -n k8s.io images pull -q $BENCH_IMAGE" 2>&1
    echo
  } | tee -a "$OUT"
done

echo | tee -a "$OUT"
echo "Compare against results/baseline-*.txt for the no-cache control." | tee -a "$OUT"
ok "Written to $OUT"
