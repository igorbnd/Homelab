# Varnish Orca on k3s

Deploys [Varnish Orca](https://www.varnish-software.com/orca/) as a virtual registry
manager in front of a three-node k3s homelab, points containerd at it, and measures
the result.

Orca caches build and runtime artifacts — container images, npm packages, Helm charts,
Go modules — at the HTTP layer, with knowledge of each registry's protocol. One node's
pull warms the cache for every other node.

## What this repo does

1. Captures a **baseline** of uncached pull times (the control group)
2. Deploys Orca as a single-replica Deployment behind a MetalLB LoadBalancer
3. Reconfigures containerd on every node to mirror through it
4. Verifies routing, fallback behaviour and metrics export
5. Measures cold vs warm pulls across nodes and proves origin-outage resilience

## Cluster this targets

| Node | Role | RAM | k3s |
|---|---|---|---|
| k3s-master01 | server | 16 GiB | v1.33.6+k3s1 |
| k3s-node2-nuc | agent | 16 GiB | v1.33.6+k3s1 |
| k3s-node3-debian | agent | 5.7 GiB | v1.34.3+k3s1 |

Addresses, the MetalLB pool and the Prometheus endpoint all live in `.env`,
which is gitignored. Nothing environment-specific is committed.

MetalLB provides LoadBalancer services (`servicelb` is disabled in k3s config).
Prometheus and Grafana run in-cluster, with the Prometheus OTLP receiver enabled.

**Known skew:** node3 runs a newer kubelet than the server. An agent newer than its
server is unsupported. Not fixed here — instead, Orca is scheduled only on master and
node2 via node affinity. node3 still *pulls through* Orca, which is a containerd
setting and unaffected. Worth resolving after the lab work, not before.

## Quick start

```bash
cp .env.example .env
./scripts/00-preflight.sh      # discovers pools, Prometheus, version skew
$EDITOR .env                   # set ORCA_LB_IP and the Prometheus endpoints

./scripts/01-baseline.sh       # BEFORE anything else — captures the control group
./scripts/02-deploy.sh         # renders manifests from .env and applies them
# add DNS or /etc/hosts entries — see node/hosts-entries.txt
./scripts/03-configure-nodes.sh
./scripts/04-verify.sh
./scripts/05-benchmark.sh      # the headline demo
```

Passwordless SSH with sudo to all three nodes is assumed.

## Layout

```
manifests/     Namespace, ConfigMap, Deployment, Service
node/          registries.yaml and hosts entries for the nodes
scripts/       Numbered, run in order; 99-rollback.sh undoes everything
grafana/       Dashboard skeleton (queries need real metric names — see below)
results/       Timings and metric names land here; gitignored
```

## Design decisions worth understanding

These are the choices an interviewer would probe, so they are deliberate rather than
incidental.

### Single replica, not a DaemonSet

Free-tier Orca has no clustering. Every replica keeps its own independent in-memory
cache, so a second replica behind a round-robin Service means the same blob gets
fetched twice. Three replicas, three fetches.

A DaemonSet is worse for the same reason: one cache per node, no sharing, and you have
rebuilt exactly the "proxies without peering" anti-pattern that Orca exists to solve.

One replica maximises hit ratio at the cost of availability. The production answer is
Premium clustering (`enable_cluster` plus a `cluster.peers` list), which gives
cluster-wide request coalescing across nodes.

### Subdomain routing

Orca routes on the **first label of the Host header**, matched against the registry
`name`. So `dockerhub.orca.lan` reaches the registry named `dockerhub`, `k8s.orca.lan`
reaches `k8s`. One Service, one address, one hostname per upstream.

This is why the DNS or `/etc/hosts` step is not optional — without name resolution
every request lands on the default registry.

### Cache sizing

There is no cache-size setting on the free tier. The cache lives in memory and is
governed by the pod's memory limit combined with Varnish's `memory_target`. Here:
a 4 GiB limit at 75% gives roughly 3 GiB of usable cache.

Persistent cache (MSE4, `varnish.storage`) is a Premium feature. Consequence: a pod
restart empties the cache. Expected, not a bug.

### Two remotes on Docker Hub

The `dockerhub` registry lists `docker.io` first and `mirror.gcr.io` second, using the
default `fallback` load balancer policy. The second is tried only if the first fails or
returns 5xx. Free resilience, and a good illustration of the remotes model.

## Rough edges to expect

**Chicken-and-egg on Orca's own image.** Once the mirror is live, pulling
`varnish/orca` routes through Orca itself. `02-deploy.sh` pre-pulls the image on every
node to sidestep this, but the real safeguard is k3s's upstream fallback — verify it
in `04-verify.sh` rather than assuming it.

**`:latest` always makes a manifest call.** Mutable tags are revalidated against the
upstream on every request, so even a cache hit produces a small round trip. The large
blobs still come from cache. Correct behaviour; understanding why is the point.

**Plain HTTP inside the LAN.** Fine for a lab, wrong for production. Orca supports
HTTPS listeners with self-signed certificates or ACME.

**Single point of failure.** One replica means an Orca outage falls back to upstream —
slower but working, assuming fallback is configured. A real deployment runs a peered
tier per region.

## Grafana

`grafana/orca-dashboard.json` ships with `TODO_` placeholders instead of metric names.
This is intentional: the exported series depend on the Orca version and exporter mode,
and invented names produce empty panels.

Run `scripts/06-discover-metrics.sh` after generating some traffic. It lists the series
Prometheus actually holds and writes them to `results/orca-metric-names.txt`. Fill those
into the dashboard.

## Rollback

```bash
./scripts/99-rollback.sh
```

Removes `registries.yaml` from every node, restarts k3s in the correct order (agents
first, server last), and deletes the namespace.

## References

- [Orca documentation](https://www.varnish-software.com/orca/docs/)
- [Orca configuration reference](https://www.varnish-software.com/orca/docs/configuration/)
- [Orca on GitHub](https://github.com/varnish/orca)
- [k3s private registry configuration](https://docs.k3s.io/installation/private-registry)
