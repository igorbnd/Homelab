#!/usr/bin/env bash
# Creates the docker-proxy and npm-proxy repos on Nexus via its REST API.
# Idempotent: safe to re-run (e.g. after a pod restart, since nexus-data is
# emptyDir and config doesn't survive -- see manifests/nexus/20-deployment.yaml).
#
# Request bodies below were built from the LIVE instance's own Swagger spec
# (GET /service/rest/swagger.json), not guessed -- Sonatype's own docs punt to
# "use the Swagger UI" rather than documenting the schema in prose.
source "$(dirname "${BASH_SOURCE[0]}")/../_lib.sh"

NEXUS_URL="http://${NEXUS_LB_IP}:8081"
NEXUS_PW=$(kubectl -n nexus exec deploy/nexus -- cat /nexus-data/admin.password 2>/dev/null)
[[ -n "$NEXUS_PW" ]] || fail "Could not read Nexus admin password (pod not ready, or password already rotated)."
AUTH=(-u "admin:${NEXUS_PW}")

repo_exists() {
  curl -s "${AUTH[@]}" "$NEXUS_URL/service/rest/v1/repositories" \
    | grep -q "\"name\":\"$1\""
}

info "Accepting the CE EULA (Nexus serves NOTHING, even to admin, until this is done --"
info "found by getting 403 with the EULA-onboarding message on every request)"
DISCLAIMER=$(curl -s "${AUTH[@]}" "$NEXUS_URL/service/rest/v1/system/eula" | python3 -c 'import json,sys; print(json.load(sys.stdin)["disclaimer"])')
STATUS=$(curl -s -o /dev/null -w '%{http_code}' "${AUTH[@]}" \
  -H 'Content-Type: application/json' -X POST \
  "$NEXUS_URL/service/rest/v1/system/eula" \
  --data-binary "$(python3 -c 'import json,sys; print(json.dumps({"accepted": True, "disclaimer": sys.argv[1]}))' "$DISCLAIMER")")
[[ "$STATUS" == "204" ]] && ok "EULA accepted" || fail "EULA accept failed (status $STATUS)"

info "Enabling anonymous read access (matches Orca's plain-HTTP-on-the-LAN posture)"
STATUS=$(curl -s -o /dev/null -w '%{http_code}' "${AUTH[@]}" \
  -H 'Content-Type: application/json' -X PUT \
  "$NEXUS_URL/service/rest/v1/security/anonymous" \
  -d '{"enabled": true, "userId": "anonymous", "realmName": "NexusAuthorizingRealm"}')
[[ "$STATUS" == "200" ]] && ok "anonymous access enabled" || fail "anonymous access enable failed (status $STATUS)"

info "Enabling the Docker Bearer Token realm (anonymous access alone isn't enough --"
info "anonymous docker pulls 403 without this realm active, found by testing live)"
STATUS=$(curl -s -o /dev/null -w '%{http_code}' "${AUTH[@]}" \
  -H 'Content-Type: application/json' -X PUT \
  "$NEXUS_URL/service/rest/v1/security/realms/active" \
  -d '["NexusAuthenticatingRealm","DockerToken"]')
[[ "$STATUS" == "204" ]] && ok "DockerToken realm active" || fail "enabling DockerToken realm failed (status $STATUS)"

info "Docker proxy repo (docker.io via registry-1.docker.io, connector on :8083)"
if repo_exists docker-hub-proxy; then
  ok "docker-hub-proxy already exists, skipping"
else
  STATUS=$(curl -s -o /tmp/nexus-docker-resp.json -w '%{http_code}' "${AUTH[@]}" \
    -H 'Content-Type: application/json' \
    -X POST "$NEXUS_URL/service/rest/v1/repositories/docker/proxy" \
    -d '{
      "name": "docker-hub-proxy",
      "online": true,
      "storage": {"blobStoreName": "default", "strictContentTypeValidation": true},
      "docker": {"v1Enabled": false, "forceBasicAuth": false, "httpPort": 8083},
      "dockerProxy": {"indexType": "HUB"},
      "proxy": {"remoteUrl": "https://registry-1.docker.io", "contentMaxAge": 1440, "metadataMaxAge": 1440},
      "negativeCache": {"enabled": true, "timeToLive": 1440},
      "httpClient": {"blocked": false, "autoBlock": true}
    }')
  [[ "$STATUS" == "201" ]] && ok "created docker-hub-proxy" || fail "docker-hub-proxy create failed (status $STATUS): $(cat /tmp/nexus-docker-resp.json)"
fi

info "npm proxy repo (registry.npmjs.org, via /repository/npm-proxy/)"
if repo_exists npm-proxy; then
  ok "npm-proxy already exists, skipping"
else
  STATUS=$(curl -s -o /tmp/nexus-npm-resp.json -w '%{http_code}' "${AUTH[@]}" \
    -H 'Content-Type: application/json' \
    -X POST "$NEXUS_URL/service/rest/v1/repositories/npm/proxy" \
    -d '{
      "name": "npm-proxy",
      "online": true,
      "storage": {"blobStoreName": "default", "strictContentTypeValidation": true},
      "proxy": {"remoteUrl": "https://registry.npmjs.org", "contentMaxAge": 1440, "metadataMaxAge": 1440},
      "negativeCache": {"enabled": true, "timeToLive": 1440},
      "httpClient": {"blocked": false, "autoBlock": true}
    }')
  [[ "$STATUS" == "201" ]] && ok "created npm-proxy" || fail "npm-proxy create failed (status $STATUS): $(cat /tmp/nexus-npm-resp.json)"
fi

rm -f /tmp/nexus-docker-resp.json /tmp/nexus-npm-resp.json
echo
ok "Repos ready:"
echo "  docker pull ${NEXUS_LB_IP}:8083/library/<image>:<tag>"
echo "  npm install --registry=http://${NEXUS_LB_IP}:8081/repository/npm-proxy/ <pkg>@<version>"
