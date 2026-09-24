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
manifests/     Namespace, ConfigMap, Deployment, Service
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

**Single replica, not a DaemonSet or multi-replica Deployment.** Free-tier Orca has
no clustering. Each replica keeps an independent in-memory cache, so extra replicas
fragment the cache and refetch the same blobs — recreating the "proxies without
peering" anti-pattern Orca exists to solve. A DaemonSet is worse for the same reason.
One replica maximises hit ratio at the cost of availability. The production answer is
Premium clustering (`enable_cluster` plus `cluster.peers`).

**Subdomain routing.** Orca routes on the first label of the Host header, matched
against the registry `name`. `dockerhub.orca.lan` → registry named `dockerhub`.
One Service, one address, one hostname per upstream. DNS or `/etc/hosts` entries are
therefore mandatory, not optional.

**Cache sizing via memory limit.** No cache-size setting exists on the free tier.
The cache is in-memory, governed by the pod memory limit × `memory_target` (4 GiB ×
75% ≈ 3 GiB usable). MSE4 persistence is Premium. A pod restart empties the cache —
expected, not a bug.

**Two remotes on dockerhub.** `docker.io` then `mirror.gcr.io`, using the default
`fallback` policy. Free resilience and a good illustration of the remotes model.

**Grafana queries are `TODO_` placeholders.** Deliberate. Orca's exported series
depend on version and exporter mode; invented metric names produce empty panels.
Run `scripts/06-discover-metrics.sh` and fill in real names. **Do not guess metric
names to make the dashboard look finished.**

## Current state

Orca is deployed and has been running in the `orca` namespace on `k3s-node2-nuc` for
several days. Firewall testing against the `npmjs` registry is well underway — see
`results/notes.md` (2026-09-19 entries) for confirmed findings: the Artifact Firewall
does not evaluate OCI/Docker traffic at all, has a reproducible parsing bug on
hyphenated npm package names that lets a matching deny rule slip through at the
tarball-request step, and there's a short startup window where the OSV ruleset hasn't
finished loading yet (~3s) during which traffic defaults to allow. ~228k real OSV
advisories load from `github.com/varnish/osv-rules` (npm) and refresh hourly.

Not yet done: the Grafana dashboard is still the 4-panel cache-only skeleton with
`TODO_` markers (no firewall panels), and the JFrog/Nexus comparison track (see
"Comparison scope" below) hasn't started.

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

5. Resilience demo (upstream blocked, pull still succeeds)
6. npm or Helm chart caching through Orca, proving it isn't images-only
7. HTTPS listener with a self-signed certificate

If only item 1 lands, there is still something real to talk about. Don't sacrifice a
working demo for a longer feature list.
