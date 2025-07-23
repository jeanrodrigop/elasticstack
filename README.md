# Elastic Stack — Modular Observability with Docker Compose

A complete and **modular** Elastic Stack for *homelab* and small
production setups. The core (Elasticsearch + Kibana) works on its own, and the
optional components are enabled on demand with `-f compose.<module>.yaml`.

The **default shipper is the Elastic Agent managed by Fleet**. The classic Beats
(Filebeat, Metricbeat, Auditbeat, Heartbeat) exist only as *legacy* fallback
modules.

---

## Table of Contents

- [Elastic Stack — Modular Observability with Docker Compose](#elastic-stack--modular-observability-with-docker-compose)
  - [Table of Contents](#table-of-contents)
  - [Architecture](#architecture)
  - [Directory structure](#directory-structure)
  - [Prerequisites](#prerequisites)
  - [Quick start](#quick-start)
  - [Available modules](#available-modules)
  - [Run examples](#run-examples)
  - [Explanation of each module](#explanation-of-each-module)
    - [Core — `compose.yaml`](#core--composeyaml)
    - [Elastic Agent — `compose.agent.yaml` (default)](#elastic-agent--composeagentyaml-default)
    - [Logstash — `compose.logstash.yaml`](#logstash--composelogstashyaml)
    - [APM — `compose.apm.yaml`](#apm--composeapmyaml)
    - [Legacy — Beats](#legacy--beats)
  - [Demo applications](#demo-applications)
  - [Security](#security)
  - [Fleet \& Elastic Agent](#fleet--elastic-agent)
  - [Data persistence](#data-persistence)
  - [Environment variables](#environment-variables)
  - [Troubleshooting](#troubleshooting)
  - [Future expansion](#future-expansion)
  - [Screenshots](#screenshots)

---

## Architecture

```
                         ┌──────────────────────────────────────────┐
                         │                CORE (always)             │
                         │                                          │
   browser    ─────────▶ │   Kibana  ◀──────▶  Elasticsearch        │
   :5601                 │   (Fleet-ready)      (single-node, auth) │
                         │        ▲                  ▲              │
                         └────────┼──────────────────┼──────────────┘
                                  │ network: elastic  │
        ┌─────────────────────────┼───────────────────┼───────────────────────┐
        │ OPTIONAL MODULES         │                   │                       │
        │                         │                   │                       │
        │  compose.agent.yaml ─▶ Fleet Server ──▶ Elastic Agent (System/Docker)│
        │  compose.logstash.yaml ─▶ Logstash ───────────────┘                  │
        │  compose.apm.yaml ─────▶ APM Server                                   │
        │  compose.{filebeat,metricbeat,auditbeat,heartbeat}.yaml ─▶ Beats      │
        └──────────────────────────────────────────────────────────────────────┘
```

All components share the dedicated bridge network `elastic` and resolve
each other by **service name** (`elasticsearch`, `kibana`,
`fleet-server`, ...).

---

## Directory structure

```
elasticstack/
├── compose.yaml                 # CORE: Elasticsearch + Kibana + setup
├── compose.agent.yaml           # Elastic Agent + Fleet Server  (default)
├── compose.logstash.yaml        # Logstash
├── compose.apm.yaml             # APM Server
├── compose.filebeat.yaml        # legacy
├── compose.metricbeat.yaml      # legacy
├── compose.auditbeat.yaml       # legacy
├── compose.heartbeat.yaml       # legacy
├── compose.demo.yaml            # demo app: Python/Flask (APM test workload)
├── compose.railsdemo.yaml       # demo app: Ruby on Rails + PostgreSQL
├── sample.env                   # variables template (copy to .env)
├── Makefile                     # shortcuts: make up / down / logs ...
├── .gitignore
├── README.md
├── configs/
│   ├── kibana/kibana.yml         # config + Fleet pre-configuration
│   ├── agent/                    # README + standalone example
│   ├── apm/apm-server.yml
│   ├── logstash/
│   │   ├── config/logstash.yml
│   │   └── pipeline/logstash.conf
│   ├── filebeat/filebeat.yml
│   ├── metricbeat/metricbeat.yml
│   ├── auditbeat/auditbeat.yml
│   └── heartbeat/heartbeat.yml
├── demo/                        # Python/Flask demo app source
├── rails-demo/                  # Ruby on Rails demo app source (+ PostgreSQL)
└── volumes/                      # OPTIONAL bind mounts (named volumes by default)
    ├── elasticsearch/
    ├── kibana/
    └── logstash/
```

---

## Prerequisites

- Docker Engine 24+ and the **Docker Compose v2** plugin (`docker compose`, no hyphen).
- **`vm.max_map_count` ≥ 262144** on the host (Elasticsearch requirement):

  ```bash
  # immediate (until reboot)
  sudo sysctl -w vm.max_map_count=262144

  # persistent
  echo 'vm.max_map_count=262144' | sudo tee /etc/sysctl.d/99-elasticsearch.conf
  sudo sysctl --system
  ```

- Enough free memory for the limits defined in `.env` (the core requires
  ~3 GB with the default values).

---

## Quick start

```bash
# 1. Create your .env from the template
cp sample.env .env

# 2. EDIT the .env — at a minimum:
#    ELASTIC_PASSWORD, KIBANA_PASSWORD and KIBANA_ENCRYPTION_KEY
#    (generate the key with: openssl rand -hex 32)

# 3. Bring up only the core
docker compose up -d

# 4. Watch the health of the services
docker compose ps

# 5. Access Kibana
#    http://localhost:5601   —   user: elastic   password: $ELASTIC_PASSWORD
```

Or, using the Makefile:

```bash
make up                          # core
make MODULES="agent" up          # core + Elastic Agent
make ps
make logs
```

---

## Available modules

| File                        | Service(s)                  | Default? | Purpose                                    |
|-----------------------------|-----------------------------|:------:|--------------------------------------------|
| `compose.yaml`              | elasticsearch, kibana, setup | core   | Mandatory core, works on its own           |
| `compose.agent.yaml`        | fleet-server, elastic-agent | ✅ yes | Collect logs/metrics/Docker via Fleet      |
| `compose.logstash.yaml`     | logstash                    | —      | Ingestion/transformation pipeline          |
| `compose.apm.yaml`          | apm-server                  | —      | APM / application tracing                  |
| `compose.filebeat.yaml`     | filebeat                    | legacy | Container logs (fallback)                  |
| `compose.metricbeat.yaml`   | metricbeat                  | legacy | Host/Docker metrics (fallback)            |
| `compose.auditbeat.yaml`    | auditbeat                   | legacy | Host audit/FIM (fallback)                  |
| `compose.heartbeat.yaml`    | heartbeat                   | legacy | Uptime/synthetics (fallback)               |
| `compose.demo.yaml`         | error-simulator (Python)    | demo   | APM test workload: traces/logs/metrics     |
| `compose.railsdemo.yaml`    | rails-* (Rails + Postgres)  | demo   | APM test workload + PostgreSQL dependency  |

---

## Run examples

> Tip: always use the **same set of `-f`** for `up`, `down`, `logs`, etc.
> The `Makefile` takes care of this via `MODULES="..."`.

**Core only**
```bash
docker compose up -d
```

**Core + Elastic Agent (recommended)**
```bash
docker compose -f compose.yaml -f compose.agent.yaml up -d
```

**Core + Logstash**
```bash
docker compose -f compose.yaml -f compose.logstash.yaml up -d
```

**Core + APM**
```bash
docker compose -f compose.yaml -f compose.apm.yaml up -d
```

**Core + legacy modules (e.g. Filebeat + Metricbeat)**
```bash
docker compose \
  -f compose.yaml \
  -f compose.filebeat.yaml \
  -f compose.metricbeat.yaml \
  up -d
```

**Full stack (Agent + Logstash + APM)**
```bash
docker compose \
  -f compose.yaml \
  -f compose.agent.yaml \
  -f compose.logstash.yaml \
  -f compose.apm.yaml \
  up -d
```

**APM + Agent + demo apps (Python & Rails test workloads)**
```bash
make MODULES="apm agent demo railsdemo" up
```

**Shut down** (keeping the data):
```bash
docker compose -f compose.yaml -f compose.agent.yaml down
```

**Shut down and delete the data volumes**:
```bash
docker compose -f compose.yaml -f compose.agent.yaml down -v
```

---

## Explanation of each module

### Core — `compose.yaml`
- **setup**: ephemeral container. Waits for Elasticsearch to become *healthy* and sets the
  password of the `kibana_system` user (least-privilege principle). Exits with 0.
- **elasticsearch**: single-node cluster, `xpack.security` enabled over HTTP,
  `memlock`, `ulimits`, heap controlled by `ES_JAVA_HEAP`, data in a named
  volume, healthcheck on `_cluster/health`.
- **kibana**: UI + Fleet control plane. Connects as `kibana_system` and is
  **pre-configured** ([`configs/kibana/kibana.yml`](configs/kibana/kibana.yml))
  with the Fleet policies, output and Fleet Server hosts — the stack is born
  ready for the Agent to enroll.

### Elastic Agent — `compose.agent.yaml` (default)
- **fleet-server**: Elastic Agent in Fleet Server mode. Generates its own *service
  token* from the `elastic` user (no manual token) and uses the
  `fleet-server-policy` policy.
- **elastic-agent**: Managed Agent that self-enrolls into the
  `Elastic Agent Observability` policy (**System** + **Docker** integrations already
  included). Mounts `docker.sock` and `/hostfs` to see the host and containers.

### Logstash — `compose.logstash.yaml`
Pipeline with **Beats (5044)** and **TCP/JSON (5000)** inputs, output to
`logs-*` indices. Pipeline and settings come from [`configs/logstash/`](configs/logstash/)
(bind mount) — edit and restart the container, no rebuild.

### APM — `compose.apm.yaml`
Standalone APM Server on port **8200**. Applications send traces using the
`APM_SECRET_TOKEN`. Config in [`configs/apm/apm-server.yml`](configs/apm/apm-server.yml).
*(Alternative: use the APM integration inside a Fleet policy.)*

### Legacy — Beats
Each Beat is **independent**, uses the **same network** as the core, points to the
**core's Elasticsearch** and reads variables from `.env`. Use only if you still
standardize on Beats; otherwise prefer the Elastic Agent.
- **filebeat**: autodiscover of Docker container logs.
- **metricbeat**: `system` (via `/hostfs`) + `docker` modules.
- **auditbeat**: `file_integrity` + `auditd` (see the warning about conflict with the
  host's `auditd` in the config file).
- **heartbeat**: HTTP/TCP/ICMP monitors (monitors ES and Kibana by default).

---

## Demo applications

Two ready-to-run sample apps generate **traces, logs, metrics and
dependencies**, so you can exercise APM and end-to-end data correlation. Both
send traces to the **APM Server** and print trace-correlated **ECS-JSON logs**
to stdout for the **Elastic Agent** to collect — so they need the `apm` and
`agent` modules running.

| Module                   | App                        | Port | Highlights                                                  |
|--------------------------|----------------------------|:----:|-------------------------------------------------------------|
| `compose.demo.yaml`      | Python / Flask             | 8000 | Random errors, self-driving load; traces + errors + metrics |
| `compose.railsdemo.yaml` | Ruby on Rails + PostgreSQL | 3000 | Saves to Postgres → **PostgreSQL dependency** in APM        |

- **`demo`** ([demo/](demo/)) — a Flask "shop" that randomly raises exceptions
  and drives its own traffic. Service **`python-error-simulator`**.
- **`railsdemo`** ([rails-demo/](rails-demo/)) — a Rails API that saves "orders"
  to PostgreSQL and fails on purpose, plus a `curl` load-generator sidecar.
  Service **`ruby-rails-error-simulator`**; its `pg` queries make **postgresql**
  show up under **APM → Dependencies** and in the **Service Map**.

**Bring both up, alongside APM + Agent:**

```bash
make MODULES="apm agent demo railsdemo" up

# equivalent raw command (first run builds the images):
docker compose -f compose.yaml -f compose.apm.yaml -f compose.agent.yaml \
               -f compose.demo.yaml -f compose.railsdemo.yaml up -d --build
```

**Where to look in Kibana** (http://localhost:5601 → **APM**):

- **Services** → `python-error-simulator` and `ruby-rails-error-simulator`.
- **Errors** → the random exceptions, grouped by type.
- **Dependencies** → **postgresql** (from the Rails app).
- **Service Map** → both services, with the Rails → postgresql edge.
- Open a trace → the spans waterfall, related **Errors**, and the **Logs** tab
  (lines sharing the trace's `trace.id`).

> **Log ↔ trace correlation** requires the log collector to parse the JSON
> stdout into fields. Filebeat honours the container's `co.elastic.logs/json.*`
> labels out of the box; for the Elastic Agent Docker integration there is a
> one-time toggle — see
> [demo/README.md](demo/README.md#making-log--trace-correlation-work).

Each app has its own README with endpoints and tuning:
[demo/README.md](demo/README.md) · [rails-demo/README.md](rails-demo/README.md).

---

## Security

- `xpack.security` **enabled**: every call requires authentication.
- Admin user: **`elastic`** / `ELASTIC_PASSWORD`.
- Kibana uses **`kibana_system`** (least privilege), configured by `setup`.
- **TLS disabled by default** (HTTP) to simplify the homelab. The services
  communicate within the isolated Docker network `elastic`.

> ⚠️ **Before exposing to the network/Internet**, change all passwords, set a
> random `KIBANA_ENCRYPTION_KEY` and **enable TLS**:
> generate certificates (e.g. `elasticsearch-certutil`), mount them, and switch
> `xpack.security.http.ssl.enabled` to `true` in Elasticsearch and the
> `http://` endpoints to `https://` in Kibana/Agent/Beats.

---

## Fleet & Elastic Agent

The pre-configuration in [`configs/kibana/kibana.yml`](configs/kibana/kibana.yml)
automatically creates:

- **Fleet Server Policy** (`fleet-server-policy`) — used by `fleet-server`.
- **Elastic Agent Observability** (`agent-policy-observability`) — default
  policy with **System** + **Docker**, used by `elastic-agent`.
- **Output** pointing to the core's Elasticsearch and **Fleet Server host**
  `http://fleet-server:8220`.

To collect more things, edit this policy in **Kibana → Fleet → Agent
policies** and add integrations (Nginx, PostgreSQL, Redis, **Kubernetes**...),
or extend `xpack.fleet.agentPolicies` in `kibana.yml`.

**Standalone** mode (without Fleet): see
[`configs/agent/README.md`](configs/agent/README.md).

---

## Data persistence

By default we use **named volumes** managed by Docker:
`elastic-stack-es-data`, `elastic-stack-kibana-data`,
`elastic-stack-logstash-data`, `elastic-stack-agent-data` and those of the Beats.

- They survive `down`; they are removed only with `down -v`.
- Backup: `docker run --rm -v elastic-stack-es-data:/data -v "$PWD:/backup" busybox tar czf /backup/es-data.tgz /data`.
- Prefer **bind mounts** in `./volumes/`? See
  [`volumes/README.md`](volumes/README.md) (remember the `chown 1000:0`).

---

## Environment variables

All of them are documented in [`sample.env`](sample.env), organized by block:
**Global, Elasticsearch, Kibana, Fleet, Elastic Agent, Logstash, APM** and
**legacy Beats**. Key points:

| Variable                | Required    | Note                                              |
|-------------------------|:-----------:|---------------------------------------------------|
| `STACK_VERSION`         | yes         | Single version for all images                     |
| `ELASTIC_PASSWORD`      | yes         | Password of the `elastic` superuser               |
| `KIBANA_PASSWORD`       | yes         | Password of `kibana_system`                       |
| `KIBANA_ENCRYPTION_KEY` | yes         | ≥ 32 chars, stable (`openssl rand -hex 32`)       |
| `ES_JAVA_HEAP`/`ES_MEM_LIMIT` | —     | Heap ~50% of the container's memory limit         |
| `*_CPU_LIMIT`/`*_MEM_LIMIT` | —       | CPU/memory limits per service                     |

---

## Troubleshooting

- **Elasticsearch restarts / `max virtual memory areas` too low** → adjust
  `vm.max_map_count` (see [Prerequisites](#prerequisites)).
- **Kibana stuck on `Kibana server is not ready yet`** → wait; the
  healthcheck's `start_period` is 2 min. Check `docker compose logs kibana`
  and whether `setup` finished successfully (`docker compose logs setup`).
- **Agent does not show up in Fleet** → confirm the core is *healthy* and check
  `docker compose -f compose.yaml -f compose.agent.yaml logs fleet-server`.
- **`down` does not remove a module** → use the **same `-f`** as the `up` (or
  `make MODULES="..." down`).
- **Permission denied on data bind mount** → `sudo chown -R 1000:0 volumes/*`.

---

## Future expansion

The architecture was designed to grow without rewriting the core:

- **Kubernetes**: add the *Kubernetes* integration to the Agent policy (or run
  the Elastic Agent as a DaemonSet in the cluster pointing to this Fleet Server).
- **More integrations**: Nginx, PostgreSQL, Redis, Kafka — all via the Fleet UI.
- **High availability**: evolve the single-node Elasticsearch into multi-node,
  add a second Fleet Server behind a load balancer.
- **New pipelines**: add files in `configs/logstash/pipeline/`.
- **New optional component**: just create `compose.<new>.yaml` reusing
  the `elastic` network and the `.env` variables.

---

## Screenshots

The stack in action with both demo apps streaming data — Elastic Agent shipping
host metrics & logs, and Elastic APM tracing the Python and Ruby services
(PostgreSQL shows up as a dependency). Click any image to enlarge.

<table>
  <tr>
    <td align="center" width="33%"><a href="images/Screenshot_000605.png"><img src="images/Screenshot_000605.png" width="100%" alt="Kibana home"></a><br><sub>Kibana — home</sub></td>
    <td align="center" width="33%"><a href="images/Screenshot_000916.png"><img src="images/Screenshot_000916.png" width="100%" alt="Observability overview"></a><br><sub>Observability — overview</sub></td>
    <td align="center" width="33%"><a href="images/Screenshot_000745.png"><img src="images/Screenshot_000745.png" width="100%" alt="Host metrics from Elastic Agent"></a><br><sub>Host metrics (Elastic Agent)</sub></td>
  </tr>
  <tr>
    <td align="center"><a href="images/Screenshot_000852.png"><img src="images/Screenshot_000852.png" width="100%" alt="Logs in Discover"></a><br><sub>Logs in Discover</sub></td>
    <td align="center"><a href="images/Screenshot_001054.png"><img src="images/Screenshot_001054.png" width="100%" alt="APM service inventory"></a><br><sub>APM — service inventory</sub></td>
    <td align="center"><a href="images/Screenshot_001245.png"><img src="images/Screenshot_001245.png" width="100%" alt="APM service overview"></a><br><sub>APM — service overview</sub></td>
  </tr>
  <tr>
    <td align="center"><a href="images/Screenshot_001332.png"><img src="images/Screenshot_001332.png" width="100%" alt="APM transactions"></a><br><sub>APM — transactions</sub></td>
    <td align="center"><a href="images/Screenshot_001534.png"><img src="images/Screenshot_001534.png" width="100%" alt="APM trace waterfall for checkout"></a><br><sub>APM — trace waterfall (checkout)</sub></td>
    <td align="center"><a href="images/Screenshot_001359.png"><img src="images/Screenshot_001359.png" width="100%" alt="APM PostgreSQL dependency"></a><br><sub>APM — PostgreSQL dependency</sub></td>
  </tr>
  <tr>
    <td align="center"><a href="images/Screenshot_001414.png"><img src="images/Screenshot_001414.png" width="100%" alt="APM errors"></a><br><sub>APM — errors</sub></td>
    <td align="center"><a href="images/Screenshot_001438.png"><img src="images/Screenshot_001438.png" width="100%" alt="APM service metrics"></a><br><sub>APM — service metrics</sub></td>
    <td align="center"><a href="images/Screenshot_001456.png"><img src="images/Screenshot_001456.png" width="100%" alt="APM trace-correlated logs"></a><br><sub>APM — logs (trace-correlated)</sub></td>
  </tr>
</table>
