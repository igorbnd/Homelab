# CLAUDE.md — Varnish Orca on k3s

Context and working agreement for Claude Code on this project.

## What this is

Deploying [Varnish Orca](https://www.varnish-software.com/orca/) — a virtual registry
manager — into a three-node k3s homelab, pointing containerd at it, and measuring the
result.

**Why it exists:** preparation for a Solutions Engineer (Platform Engineering
Acceleration) interview at Varnish Software. One of the interviewers co-built Orca.
The goal is hands-on evidence — real numbers from a real deployment — not a summary
of the product page. Rough edges encountered along the way are *valuable*, not
failures: they are the difference between having deployed something and having read
about it.

**Deadline:** first interview 3 September. Prioritise a working demo with measurements
over completeness.

## What Orca does

Caches build and runtime artifacts (container images, npm packages, Helm charts, Go
modules, PyPI) at the HTTP layer, with knowledge of each registry's protocol. It sits
between clients and upstream registries. One node's pull warms the cache for every
other node.

The distinction that matters: a CDN distributes content *you own* outward to external
consumers. Artifact resolution is acquiring content *you don't own*, inward, for
internal consumers. Direction and ownership are both reversed, which is why CDN tooling
doesn't apply.

## Repository layout

```
manifests/     Namespace, ConfigMap, StatefulSet, headless + LoadBalancer Service
node/          registries.yaml and hosts entries to install on the nodes
scripts/       Numbered, run in order; 99-rollback.sh undoes everything
grafana/       Dashboard skeleton — queries are TODO placeholders by design
results/       Timings and metric names land here; gitignored
.env           Environment-specific values; gitignored, never commit
```

## Environment

Three-node k3s cluster: one server, two agents. Ubuntu 24.04 on the server and
node2 (16 GiB each), Debian 13 on node3 (5.7 GiB). MetalLB provides LoadBalancer
services — `servicelb` is disabled in the k3s config. Prometheus and Grafana run
in-cluster with the Prometheus OTLP receiver enabled. Flannel on `eno1`.

Actual addresses, MetalLB pool and Prometheus service names live in `.env`.
**Never commit real IPs, hostnames of external services, or credentials.**

### Known constraint: k3s version skew

`k3s-node3-debian` runs v1.34.3+k3s1 against a v1.33.6+k3s1 server. An agent newer
than its server is **unsupported**.

Deliberately not fixed. Orca is scheduled only on the server and node2 via node
affinity; node3 still pulls *through* Orca, which is a containerd setting and
unaffected. Do not propose upgrading the cluster — it is off the critical path and
carries risk before the interview.

## Design decisions — do not change these without discussion

These are deliberate and each has a reason worth being able to defend.

**2-replica StatefulSet with Premium clustering, not single-replica.** SUPERSEDES the
original single-replica decision (2026-08-28) — kept here for the reasoning trail, not
as current practice. The original problem was real: free-tier Orca has no clustering,
each replica keeps an independent in-memory cache, so extra replicas fragment the cache
and refetch the same blobs — the "proxies without peering" anti-pattern Orca exists to
solve. That problem goes away once clustering is genuinely licensed and enabled
(confirmed 2026-09-24: `addons: sup-clustering` in `license.lic`, verified live via the
boot log — `License: Nodes clustering enabled` — not just claimed). With
`enable_cluster: true` and `cluster.peers`, either replica can serve any cached object,
proxied through the mesh if it doesn't hold it locally, so 2 replicas no longer
fragments anything — it's what makes the resilience demo (kill one pod, the other still
serves) actually real instead of aspirational. Still capped at 2, matching the 2 nodes
eligible for Orca (node3 stays excluded — version skew, unchanged). A DaemonSet remains
a bad idea for the same original reason (no upper bound on fragmentation, and now no
bound on cluster peer count either). StatefulSet, not Deployment, because clustering's
static `peers` list needs stable per-pod network identity — Orca has no Kubernetes-native
peer discovery, only a static list or EC2 auto-discovery — which only a StatefulSet's
predictable pod names + a headless Service actually provide.

**Subdomain routing.** Orca routes on the first label of the Host header, matched
against the registry `name`. `dockerhub.orca.lan` → registry named `dockerhub`.
One Service, one address, one hostname per upstream. DNS or `/etc/hosts` entries are
therefore mandatory, not optional.

**Hybrid RAM + MSE4 disk cache, not memory-only.** SUPERSEDES the original memory-only
decision — kept here for the reasoning trail. The original constraint was real: no
cache-size setting exists on the free tier, so sizing was pod memory limit ×
`memory_target` only (5 GiB × 60% ≈ 3 GiB), and a pod restart emptied the cache, which
was "expected, not a bug" because there was no alternative. MSE4 persistence
(`addons: sup-persistence`, confirmed licensed the same way clustering was) removes that
constraint: `varnish.storage.stores` adds a disk-backed store (currently 15G,
deliberately bigger than the RAM cache — the actual point of MSE4 is extending the cache
past available memory, not merely surviving a restart) via a `local-path` PVC per
StatefulSet replica. `memory_target` still governs the RAM tier and still auto-adjusts to
the pod's real cgroup limit at startup regardless of the literal value written in
config — confirmed in the boot log, not assumed. A restart no longer empties everything;
verify this is actually true after deploying rather than trusting the docs' claim.

**Two remotes on dockerhub.** `docker.io` then `mirror.gcr.io`, using the default
`fallback` policy. Free resilience and a good illustration of the remotes model.

**Grafana queries are `TODO_` placeholders.** Deliberate. Orca's exported series
depend on version and exporter mode; invented metric names produce empty panels.
Run `scripts/06-discover-metrics.sh` and fill in real names. **Do not guess metric
names to make the dashboard look finished.**

## Current state

Orca runs as a 2-replica StatefulSet (`orca-0` on `k3s-node2-nuc`, `orca-1` on
`k3s-master01`) with Premium clustering and MSE4 persistence both live — see "Design
decisions" above for why, and `results/notes.md` (2026-09-24 entries) for how it was
verified: license genuinely covers `sup-clustering`/`sup-persistence` (not just claimed),
persistence confirmed via a real pod restart (`Revived 16 objects`, then a 10x-faster
refetch of the same blob), cluster resilience confirmed by force-killing one replica and
still getting served from the survivor. One open item from that session: the
client-facing LoadBalancer was slow once through a freshly-recreated peer, not yet
explained (restart-timing artifact vs. a real replication gap) — don't claim
"zero-latency-impact failover" until that's resolved.

Firewall testing against the `npmjs` registry found several confirmed, reproducible
bugs (`results/notes.md`, 2026-09-19 and 2026-09-24 entries): the Artifact Firewall
doesn't evaluate OCI/Docker traffic at all; a parsing bug on hyphenated npm package
names lets a matching deny rule slip through at the tarball-request step; a false
positive blocks a currently-patched `node-forge` version citing a CVE fixed 4 majors
earlier, breaking an entire `create-react-app` install; every documented malicious-npm
incident tried (2018 through a May 2026 credential-stealer) had already been scrubbed
from the live registry by npm's own security team before it could be tested. ~228k real
OSV advisories load from `github.com/varnish/osv-rules` (npm) and refresh hourly.

Grafana dashboard (`grafana/orca-dashboard.json`) has all 7 panels wired to real,
live-verified metric names — no `TODO_` markers. The JFrog/Nexus comparison track (see
"Comparison scope" below): Nexus is fully deployed, configured, and benchmarked; JFrog
is scaffolded via its official Helm chart but blocked on obtaining a trial license.

## Comparison scope

Beyond Orca alone, the interview goal now includes being able to speak from hands-on
experience about JFrog Artifactory and Sonatype Nexus as points of comparison — not to
become an expert in either, just enough for a credible "I tried it, here's how it
compares" narrative. Decisions locked in for this track (see the full plan for detail):

- **No containerd wiring for JFrog/Nexus.** Orca stays the only tool wired into
  `registries.yaml` (k3s only supports one mirror endpoint set per upstream, and
  restarting k3s is already flagged above as the riskiest step in this repo). JFrog and
  Nexus get their own Service + subdomain, benchmarked with direct `docker pull`/`skopeo`
  against their Docker-remote endpoint.
- **JFrog = self-hosted trial** (`artifactory-pro` image, license from
  jfrog.com/start-free) — the free `artifactory-oss` image cannot proxy Docker at all.
- **Nexus = Nexus Repository OSS 3** (`sonatype/nexus3`) — genuinely free, no trial
  needed, supports Docker-proxy and npm-proxy out of the box.
- Comparison covers Docker image caching **and** npm caching (same test packages as the
  Orca firewall work: `ms`, `left-pad`, `minimist`).
- No fake parity for Orca's Artifact Firewall — Nexus OSS has nothing built-in, JFrog's
  Xray scanner is a separate product not guaranteed to be in the trial. Confirm what's
  actually enabled before claiming a comparison.
- New dirs follow the existing manifest/script numbering convention:
  `manifests/jfrog/`, `manifests/nexus/`, `scripts/jfrog/`, `scripts/nexus/`.

## Run order

```bash
./scripts/00-preflight.sh        # discovers MetalLB pool, Prometheus, version skew
$EDITOR .env                     # set ORCA_LB_IP, PROM_OTLP_ENDPOINT, PROM_QUERY_URL, NODES
./scripts/01-baseline.sh         # MUST run before the mirror is configured
./scripts/02-deploy.sh           # renders manifests from .env, applies, pre-pulls image
# add DNS wildcard *.orca.lan or /etc/hosts entries on all nodes
./scripts/03-configure-nodes.sh  # installs registries.yaml, restarts k3s (agents first)
./scripts/04-verify.sh
./scripts/05-benchmark.sh        # the headline demo
./scripts/06-discover-metrics.sh # then fill in grafana/orca-dashboard.json
./scripts/07-resilience-demo.sh <node>
```

`scripts/01-baseline.sh` is the one step that cannot be redone later. It captures
uncached pull times as a control group. If it gets skipped, there is no "before" to
compare against.

## Working agreement

**Ask before destructive actions.** Restarting k3s, editing `/etc/rancher/k3s/`, or
deleting namespaces affects a live homelab running other workloads (Loki, Grafana,
Traefik, Longhorn, Frigate). Propose, then wait.

**Restart order matters.** Agents first (`systemctl restart k3s-agent`), server last
(`systemctl restart k3s`). Reversing this can strand agents pointing at a dead mirror
endpoint.

**Verify, don't assume.** Particularly: does k3s actually append the upstream registry
as a fallback endpoint after the mirror? Read the generated
`/var/lib/rancher/k3s/agent/etc/containerd/certs.d/docker.io/hosts.toml` rather than
trusting the documentation. This is exactly the kind of detail the interviewer will
probe.

**Record what goes wrong.** Errors, surprises and workarounds are the most valuable
output of this project. Append them to `results/notes.md` as they happen. "The
containerd mirror config took two attempts because…" is a better interview answer
than a clean run.

**Don't commit `.env` or anything under `results/`** — both are gitignored. Don't
add real IPs back into README.md or the manifests.

**Consult the docs, don't rely on memory.** Orca is recent and its configuration
surface is large:
- Configuration reference: https://www.varnish-software.com/orca/docs/configuration/
- Installation: https://www.varnish-software.com/orca/docs/installation/
- GitHub: https://github.com/varnish/orca
- k3s private registries: https://docs.k3s.io/installation/private-registry

## Known rough edges to expect

**Chicken-and-egg on Orca's own image.** Once the mirror is live, pulling
`varnish/orca` routes through Orca itself. `02-deploy.sh` pre-pulls on every node to
sidestep this, but the real safeguard is k3s's upstream fallback — verify it.

**`:latest` always makes a manifest call.** Mutable tags revalidate against the
upstream on every request, so even a cache hit produces a small round trip. Large
blobs still come from cache. Correct behaviour.

**Plain HTTP on the LAN.** Fine for a lab, wrong for production. Orca supports HTTPS
listeners with self-signed certs or ACME if there's time to demonstrate it.

**Benchmark scripts assume passwordless SSH + sudo** to all nodes, and wrap
`TIMEFORMAT` around remote commands — adjust if the remote shell isn't bash.

## Definition of done

Minimum viable, in priority order:

1. Orca deployed, containerd mirroring on all three nodes, `04-verify.sh` passing
2. `results/baseline-*.txt` and `results/benchmark-*.txt` showing a cold/warm delta
3. Grafana dashboard with real metric names and a screenshot showing real data
4. `results/notes.md` capturing what went wrong and how it was resolved

Stretch, only if items 1–4 are complete:

5. ~~Resilience demo~~ **Done, 2026-09-24** — not the original origin-outage version,
   the sharper Premium version: killed one cluster replica outright, the survivor kept
   serving previously-cached content. See `results/notes.md` for the one open caveat
   (LB-path recovery timing not yet explained).
6. npm or Helm chart caching through Orca, proving it isn't images-only
7. HTTPS listener with a self-signed certificate
8. **New:** MSE4 persistence demo (pod restart, cache survives) — **done, 2026-09-24**,
   see "Current state" and `results/notes.md`. This one's unambiguous, unlike #5's caveat.

If only item 1 lands, there is still something real to talk about. Don't sacrifice a
working demo for a longer feature list.
