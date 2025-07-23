# error-simulator — traces + logs + metrics correlation demo

A tiny Flask "shop" that **fails on purpose** so you can see Elastic correlate
the three observability signals for one application:

| Signal      | How it is produced                                   | Collected by   |
|-------------|------------------------------------------------------|----------------|
| **Traces**  | Every request is an APM transaction; DB/cache/payment work are spans | Elastic APM    |
| **Errors**  | Endpoints randomly raise exceptions                  | Elastic APM    |
| **Metrics** | Transaction/breakdown + runtime metrics from the agent | Elastic APM    |
| **Logs**    | ECS-JSON to stdout, stamped with `trace.id`          | Elastic Agent  |

A background load generator drives the endpoints, so data flows continuously —
you don't have to run `curl`.

## Prerequisites

The core stack plus the **apm** and **agent** modules must be up, and your
`.env` must be the modular-stack format (copied from `sample.env`, with
`APM_SECRET_TOKEN`, `KIBANA_ENCRYPTION_KEY`, `STACK_VERSION=9.4.2`, ...).

## Run

```bash
# from the repo root
make MODULES="apm agent demo" up

# equivalent raw command:
docker compose -f compose.yaml -f compose.apm.yaml -f compose.agent.yaml \
               -f compose.demo.yaml up -d --build
```

The app also publishes port 8000 on the host, so you can poke it yourself:

```bash
curl localhost:8000/products
curl localhost:8000/checkout
curl localhost:8000/users/7      # 404 path
```

## Where to look in Kibana (http://localhost:5601)

1. **APM** → *Services* → **python-error-simulator**
   - *Transactions* — latency/throughput per endpoint (`/products`, `/checkout`, …)
   - *Errors* — the random exceptions, grouped by type
   - *Metrics* — CPU / memory / breakdown for the service
2. Open any transaction → **Trace sample**:
   - the **spans** (DB / cache / payment) waterfall
   - the **Errors** raised in that trace
   - the **Logs** tab → log lines that share the trace's `trace.id`

## Making log ↔ trace correlation work

The app prints **ECS-JSON** to stdout with `trace.id` already embedded. For
Kibana to match those logs to a trace, the collector must parse that JSON into
fields. The container carries `co.elastic.logs/json.*` labels for this:

- **Filebeat module** (`MODULES="... filebeat"`) honours those labels out of the
  box (`hints.enabled: true`) — nothing else to do.
- **Elastic Agent Docker integration** (the default here): enable JSON parsing
  once in Kibana → *Fleet* → **Elastic Agent Observability** policy → *Docker*
  integration → *Collect logs from Docker containers* → **Advanced**, and add an
  `ndjson` parser (or turn on hints-based autodiscovery):

  ```yaml
  - ndjson:
      target: ""
      overwrite_keys: true
      add_error_key: true
      expand_keys: true
  ```

Until JSON parsing is on, the logs still arrive (the whole JSON sits in
`message`); only the automatic log↔trace link in the APM UI needs the parsed
`trace.id`.

## Tuning (env vars in `compose.demo.yaml`)

| Variable                | Default | Meaning                                  |
|-------------------------|---------|------------------------------------------|
| `ERROR_RATE`            | `0.25`  | Base probability a request fails (0–1)   |
| `LOAD_INTERVAL`         | `1.0`   | Load generator pace, ~seconds per call   |
| `ENABLE_LOAD_GENERATOR` | `true`  | Set `false` to drive traffic yourself    |
| `DEMO_PORT`             | `8000`  | Host port published for manual requests  |
