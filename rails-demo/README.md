# rails-error-simulator — APM + PostgreSQL dependency demo

A small **Rails 7.1 API** app that saves "orders" to **PostgreSQL** and fails on
purpose. It runs in parallel with the Python [demo](../demo/) and exists to show
**dependency data** in Elastic APM:

| Signal           | How it is produced                                       | Collected by   |
|------------------|----------------------------------------------------------|----------------|
| **Traces**       | Every request is an APM transaction                      | Elastic APM    |
| **Dependencies** | ActiveRecord/`pg` queries become DB spans → PostgreSQL appears as a downstream dependency | Elastic APM |
| **Errors**       | Endpoints randomly raise exceptions                      | Elastic APM    |
| **Metrics**      | Transaction/breakdown metrics from the agent             | Elastic APM    |
| **Logs**         | ECS-JSON to stdout, stamped with `trace.id`              | Elastic Agent  |

The `rails-loadgen` sidecar drives traffic, so data flows with no manual `curl`.

## Run

```bash
# from the repo root — runs alongside the python `demo` module
make MODULES="apm agent demo railsdemo" up

# equivalent raw command:
docker compose -f compose.yaml -f compose.apm.yaml -f compose.agent.yaml \
               -f compose.railsdemo.yaml up -d --build
```

Endpoints (also reachable on the host at `localhost:3000`):

| Method | Path             | Behaviour                                             |
|--------|------------------|-------------------------------------------------------|
| GET    | `/orders`        | List last 10 orders (SELECT)                          |
| POST   | `/orders`        | Create a random order (INSERT)                        |
| GET    | `/orders/random` | Same as POST, GET-friendly for the load generator     |
| GET    | `/orders/:id`    | Show one; missing id → reported 404                   |
| GET    | `/checkout`      | INSERT → charge (may fail) → UPDATE                   |
| GET    | `/boom`          | Always raises (guaranteed error)                      |
| GET    | `/health`        | Liveness (used by the container healthcheck)          |

## Where to look in Kibana (http://localhost:5601)

1. **APM → Services → `ruby-rails-error-simulator`**
   - *Transactions* — latency/throughput per route
   - *Errors* — the random exceptions, grouped by type
2. **APM → Dependencies** (or the service's *Dependencies* tab) → **postgresql**
   shows up as a downstream dependency, with its own latency/throughput.
3. **APM → Service Map** → the Rails service with an edge to **postgresql** (and
   the Python service alongside it).
4. Open any `/checkout` trace → the span waterfall shows the INSERT, the
   `payment.charge` span, and the UPDATE; the **Logs** tab shows lines sharing
   the trace's `trace.id`.

> Log↔trace correlation needs the collector to parse the JSON stdout into
> fields — same one-time toggle as the Python demo (see
> [../demo/README.md](../demo/README.md#making-log--trace-correlation-work)).

## Tuning (env vars in `compose.railsdemo.yaml`)

| Variable                | Default     | Meaning                                |
|-------------------------|-------------|----------------------------------------|
| `ERROR_RATE`            | `0.25`      | Base probability a request fails (0–1) |
| `RAILS_DEMO_PORT`       | `3000`      | Host port published for manual requests|
| `RAILS_PG_USER/PASSWORD/DB` | `rails`/`railspass`/`railsdemo` | Postgres credentials |

## Layout

```
rails-demo/
├── Gemfile                 # rails, pg, puma, elastic-apm
├── config.ru  Rakefile
├── config/                 # boot, application, environment, database, puma, routes
├── lib/ecs_apm_formatter.rb# ECS-JSON logger w/ APM trace ids
├── app/
│   ├── controllers/        # health, orders
│   └── models/             # order, payment_error
├── db/migrate/             # create_orders
├── Dockerfile  docker-entrypoint.sh
```
