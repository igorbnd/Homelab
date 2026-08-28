#!/usr/bin/env bash
# Confirms Orca is reachable, subdomain routing works, and containerd is using it.
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

FAILED=0

info "1. Service has an external address"
LB=$(kubectl -n "$ORCA_NAMESPACE" get svc orca -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
if [[ "$LB" == "$ORCA_LB_IP" ]]; then ok "EXTERNAL-IP is $LB"
else warn "Expected $ORCA_LB_IP, got '${LB:-<none>}'"; FAILED=1; fi

echo
info "2. Orca answers on the registry API"
CODE=$(curl -s -o /dev/null -w '%{http_code}' -H "Host: dockerhub.$ORCA_DOMAIN" "http://$ORCA_LB_IP/v2/" || true)
# 401 is CORRECT here -- it is the Docker registry auth handshake.
if [[ "$CODE" == "401" || "$CODE" == "200" ]]; then ok "HTTP $CODE (401 is expected: registry auth handshake)"
else warn "Unexpected HTTP $CODE"; FAILED=1; fi

echo
info "3. Subdomain routing resolves and differentiates registries"
for reg in dockerhub k8s ghcr quay; do
  if getent hosts "$reg.$ORCA_DOMAIN" >/dev/null 2>&1; then
    C=$(curl -s -o /dev/null -w '%{http_code}' "http://$reg.$ORCA_DOMAIN/v2/" || true)
    ok "$reg.$ORCA_DOMAIN -> HTTP $C"
  else
    warn "$reg.$ORCA_DOMAIN does not resolve -- add DNS or /etc/hosts entries"
    FAILED=1
  fi
done

echo
info "4. containerd hosts.toml generated on each node"
for node in $NODES; do
  echo "--- $node ---"
  ssh "$node" "sudo cat /var/lib/rancher/k3s/agent/etc/containerd/certs.d/docker.io/hosts.toml 2>/dev/null" \
    || warn "no hosts.toml on $node (registries.yaml not applied, or k3s not restarted)"
done

echo
info "5. Upstream fallback check"
echo "Look for the upstream registry listed AFTER the mirror in the hosts.toml above."
echo "If it is absent, an Orca outage means pulls fail rather than falling back."

echo
info "6. OTLP metrics export"
kubectl -n "$ORCA_NAMESPACE" logs deploy/orca --tail=200 2>/dev/null | grep -i -E 'otel|metric|export' | tail -10 \
  || warn "no otel lines in the log yet -- give it one export_interval"

echo
[[ "$FAILED" -eq 0 ]] && ok "All checks passed." || warn "Some checks need attention (see above)."
