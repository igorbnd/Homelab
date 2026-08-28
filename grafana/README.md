# Grafana dashboard

`orca-dashboard.json` is a **skeleton**. The panel queries contain `TODO_` markers
rather than invented metric names.

This is deliberate. Orca's exact exported series depend on the version and on
whether you use the OTLP push or Prometheus scrape exporter, and guessing metric
names produces a dashboard that renders four empty panels.

To fill it in:

1. Deploy Orca and let it serve some traffic (`scripts/05-benchmark.sh`).
2. Run `scripts/06-discover-metrics.sh` -- it lists the series actually present
   in Prometheus and writes them to `results/orca-metric-names.txt`.
3. Replace each `TODO_` placeholder with the real metric name.

The four panels to build, in priority order:

| Panel | What it shows | Why it matters |
|---|---|---|
| Cache hit ratio | hits / (hits + misses), as a percentage | The headline number |
| Cache vs origin bytes | bytes served from cache against bytes fetched upstream | The offload story in one graph |
| Origin request rate | requests reaching the upstream registry | Should fall sharply after warm-up |
| Fetch latency | hit latency against origin-fetch latency | Makes the speed claim concrete |

Keep it to four panels. A focused dashboard screenshots far better than a busy one.
