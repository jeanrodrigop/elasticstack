# Elastic Agent config

The default `compose.agent.yaml` runs the Elastic Agent **Fleet-managed**: there
is no local config file to edit. Policies and integrations are managed centrally
from Kibana → **Fleet**, and are pre-seeded in
[`../kibana/kibana.yml`](../kibana/kibana.yml) (policies `Fleet Server Policy`
and `Elastic Agent Observability`).

To change what the agent collects, edit the **Elastic Agent Observability**
policy in the Fleet UI (or extend `xpack.fleet.agentPolicies` in `kibana.yml`)
and add integrations: Kubernetes, Nginx, PostgreSQL, Redis, etc.

## Standalone fallback

If you ever need to run the agent **without Fleet** (air-gapped, GitOps-managed
config), use [`elastic-agent.standalone.yml.example`](elastic-agent.standalone.yml.example)
as a starting point: bind-mount it to
`/usr/share/elastic-agent/elastic-agent.yml`, drop the `FLEET_*` environment
variables from `compose.agent.yaml`, and the agent will read its inputs from the
file instead of from Fleet.
