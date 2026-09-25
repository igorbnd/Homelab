#!/usr/bin/env bash
# Cold/warm npm install through Nexus's npm-proxy repo. Run from this machine --
# npm packages are small enough that Wi-Fi bandwidth isn't the confound it is
# for docker images.
source "$(dirname "${BASH_SOURCE[0]}")/../_lib.sh"

PKG="${1:-ms@2.1.3}"
REGISTRY="http://${NEXUS_LB_IP}:8081/repository/npm-proxy/"

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
OUT="$RESULTS_DIR/nexus-benchmark-npm-$STAMP.txt"

{
  echo "Nexus npm proxy cold/warm benchmark -- $STAMP"
  echo "Package: $PKG"
  echo
} | tee "$OUT"

info "COLD (Nexus fetches from registry.npmjs.org)"
DIR1=$(mktemp -d)
{
  echo "--- COLD ---"
  ( cd "$DIR1" && TIMEFORMAT='real %3R'; time npm install --registry="$REGISTRY" "$PKG" ) 2>&1
  echo
} | tee -a "$OUT"
rm -rf "$DIR1"

info "WARM (served from Nexus's cache)"
DIR2=$(mktemp -d)
{
  echo "--- WARM ---"
  ( cd "$DIR2" && TIMEFORMAT='real %3R'; time npm install --registry="$REGISTRY" "$PKG" ) 2>&1
  echo
} | tee -a "$OUT"
rm -rf "$DIR2"

ok "Written to $OUT"
