#!/usr/bin/env bash
# Deploys JFrog Artifactory Pro (self-hosted trial) via the official Helm chart.
# NOT hand-rolled manifests like Orca/Nexus -- see manifests/jfrog/values.yaml header
# for why. Direct-pull only, not wired into containerd, per CLAUDE.md "Comparison scope".
source "$(dirname "${BASH_SOURCE[0]}")/../_lib.sh"

LICENSE_FILE="${JFROG_LICENSE_FILE:-$REPO_ROOT/jfrog-license.lic}"
[[ -f "$LICENSE_FILE" ]] || fail "No license file at $LICENSE_FILE. Get a self-hosted trial at jfrog.com/start-free, save it there (or set JFROG_LICENSE_FILE)."

info "Adding/updating the jfrog Helm repo"
helm repo add jfrog https://charts.jfrog.io >/dev/null 2>&1 || true
helm repo update jfrog >/dev/null

info "Creating namespace"
kubectl create namespace jfrog --dry-run=client -o yaml | kubectl apply -f -

info "Creating license Secret from $LICENSE_FILE"
kubectl -n jfrog create secret generic artifactory-license \
  --from-file="art.lic=$LICENSE_FILE" \
  --dry-run=client -o yaml | kubectl apply -f -

info "Installing/upgrading jfrog/artifactory (this takes several minutes -- Postgres + Artifactory + nginx)"
helm upgrade --install artifactory jfrog/artifactory \
  --namespace jfrog \
  -f "$REPO_ROOT/manifests/jfrog/values.yaml" \
  --set artifactory.license.secret=artifactory-license \
  --set artifactory.license.dataKey=art.lic \
  --set nginx.service.annotations."metallb\.universe\.tf/loadBalancerIPs"="$JFROG_LB_IP" \
  --timeout 15m \
  --wait

echo
kubectl -n jfrog get pods,svc -o wide
echo
ok "Deployed. Next: scripts/jfrog/01-configure-repos.sh (once written against the live REST/Swagger)."
