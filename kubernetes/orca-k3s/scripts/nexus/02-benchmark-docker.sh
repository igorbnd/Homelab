#!/usr/bin/env bash
# Cold/warm docker pull through Nexus's docker-hub-proxy repo.
# Runs via ctr on a wired cluster node (BENCH_NODE), NOT from this machine --
# a laptop-over-Wi-Fi pull is bandwidth-bound regardless of cache hit/miss for
# any reasonably large image, which hides the real signal.
#
# Uses `ctr images rm --sync` to force a real content-store removal before each
# pull. Even so, this ONLY gives a trustworthy "cold" number if BENCH_IMAGE (and
# anything sharing its base layers) is genuinely absent from that node's
# containerd content store beforehand -- verify with `ctr -n k8s.io images ls`
# if in doubt.
source "$(dirname "${BASH_SOURCE[0]}")/../_lib.sh"

BENCH_NODE="${BENCH_NODE:-k3s-master01}"

# BENCH_IMAGE is e.g. docker.io/library/node:latest -> library/node:latest under the proxy.
IMG_PATH="${BENCH_IMAGE#docker.io/}"
TARGET="${NEXUS_LB_IP}:8083/${IMG_PATH}"

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
OUT="$RESULTS_DIR/nexus-benchmark-docker-$STAMP.txt"

{
  echo "Nexus docker proxy cold/warm benchmark -- $STAMP"
  echo "Image: $TARGET"
  echo "Node: $BENCH_NODE (wired LAN, via ctr)"
  echo
} | tee "$OUT"

warn "This trusts that $TARGET is genuinely uncached on $BENCH_NODE. Verify with:"
warn "  ssh $BENCH_NODE \"sudo ctr -n k8s.io images ls | grep -i \$(basename $IMG_PATH)\""
read -r -p "Confirmed absent (or fine with a possibly-warm COLD number)? [y/N] " reply
[[ "$reply" =~ ^[Yy]$ ]] || fail "Aborted."

ssh "$BENCH_NODE" "sudo ctr -n k8s.io images rm --sync $TARGET >/dev/null 2>&1 || true"

info "COLD (Nexus fetches from docker.io)"
{
  echo "--- COLD ---"
  ssh "$BENCH_NODE" "TIMEFORMAT='real %3R'; time sudo ctr -n k8s.io images pull --plain-http $TARGET >/dev/null" 2>&1
  echo
} | tee -a "$OUT"

ssh "$BENCH_NODE" "sudo ctr -n k8s.io images rm --sync $TARGET >/dev/null 2>&1 || true"

info "WARM (served from Nexus's own cache, not node-local reuse)"
{
  echo "--- WARM ---"
  ssh "$BENCH_NODE" "TIMEFORMAT='real %3R'; time sudo ctr -n k8s.io images pull --plain-http $TARGET >/dev/null" 2>&1
  echo
} | tee -a "$OUT"

ok "Written to $OUT"
