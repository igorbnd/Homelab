# Grafana dashboard

`orca-dashboard.json` has 7 panels, all wired to real metric names pulled from a live
instance via `scripts/06-discover-metrics.sh` -- no `TODO_` placeholders.

Cache: hit ratio, bytes to clients vs origin, origin request rate by registry, fetch
latency. Firewall: verdicts by action, top rules firing, ruleset health.

If the metric names ever need re-verifying (new Orca version, different exporter mode):

1. Deploy Orca and let it serve some traffic (`scripts/05-benchmark.sh`).
2. Run `scripts/06-discover-metrics.sh` -- lists the series actually present in
   Prometheus, writes them to `results/orca-metric-names.txt`.
3. Diff against what's in the dashboard queries before trusting either.

Don't guess metric names to make a panel look finished -- two of the ones in here
looked obvious and were wrong (`varnish_backend_response_bodybytes` is always 0 for
Docker Hub; see the panel's own description for why).
