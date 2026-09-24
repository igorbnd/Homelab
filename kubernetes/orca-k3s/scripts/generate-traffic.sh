#!/usr/bin/env bash
#
# generate-traffic.sh — drive load through Varnish Orca to populate Grafana.
#
# Removes then re-pulls a spread of images across all three nodes, concurrently,
# for several rounds. The rmi-before-pull defeats containerd's "up to date"
# short-circuit so requests actually reach Orca. Round 1 is mostly cold (origin
# fetches); later rounds serve from cache where the working set still fits.
#
# Usage:
#   ./generate-traffic.sh            # default: 3 rounds, all nodes
#   ROUNDS=5 ./generate-traffic.sh   # more rounds = more traffic
#   NODES="nuc1 nuc2" ./generate-traffic.sh   # subset of nodes
#
# After running, wait ~10 min before screenshotting Grafana — the rate([5m])
# windows need time to fill so lines show shape rather than a single spike.

set -uo pipefail

# SSH aliases for the three nodes. Adjust to match your ~/.ssh/config.
NODES="${NODES:-nuc1 nuc2 nuc3}"
ROUNDS="${ROUNDS:-3}"

# Images span all three configured registries (docker.io, ghcr.io,
# registry.k8s.io) so every virtual registry namespace lights up in Grafana,
# not just dockerhub. Full registry prefix is included per image. Mix of sizes
# so some rounds hit cache and some trigger eviction+refetch on the ~3 GiB free
# tier — both are realistic and worth having in the graphs.
IMAGES="${IMAGES:-\
docker.io/redis:7.4 docker.io/postgres:16-alpine docker.io/nginx:alpine \
docker.io/python:3.12-slim docker.io/node:20-alpine docker.io/golang:1.23-alpine \
docker.io/ruby:3.3-alpine docker.io/memcached:1.6 docker.io/mariadb:11 \
docker.io/httpd:alpine docker.io/mongo:7 docker.io/rabbitmq:3.13 \
docker.io/haproxy:2.9 docker.io/traefik:v3.1 docker.io/caddy:2 \
docker.io/busybox:latest docker.io/alpine:3.20 docker.io/debian:12 \
ghcr.io/fluxcd/flux-cli:v2.3.0 ghcr.io/stargz-containers/node:20-esgz \
registry.k8s.io/coredns/coredns:v1.11.1 registry.k8s.io/metrics-server/metrics-server:v0.7.1 \
registry.k8s.io/pause:3.9}"

echo "Nodes:  $NODES"
echo "Rounds: $ROUNDS"
echo "Images: $(echo $IMAGES | wc -w) per node per round"
echo

for round in $(seq 1 "$ROUNDS"); do
  echo "=== round $round/$ROUNDS starting $(date +%H:%M:%S) ==="
  for node in $NODES; do
    ssh "$node" "for img in $IMAGES; do \
      sudo k3s crictl rmi \$img >/dev/null 2>&1; \
      sudo k3s crictl pull \$img >/dev/null 2>&1; \
    done" &
  done
  wait
  echo "=== round $round/$ROUNDS done $(date +%H:%M:%S) ==="
done

echo
echo "Traffic generation complete."
echo "Check Orca counters (substitute current pod IP):"
echo "  kubectl -n orca get pod -o wide"
echo "  ssh nuc2 \"curl -s http://<POD_IP>:9464/metrics | grep -E 'varnish_main_(backend_req|client_requests)'\""
echo
echo "Then wait ~10 min and screenshot Grafana."
