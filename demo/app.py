#!/usr/bin/env python3
"""
error-simulator — a tiny Flask "shop" that fails on purpose.

What it demonstrates (the whole point of this demo):

  * TRACES   — every request is an APM transaction; simulated DB / cache /
               payment work shows up as spans.
  * ERRORS   — it randomly raises exceptions, which the Elastic APM agent
               captures and links back to the originating trace.
  * METRICS  — the APM agent ships transaction/breakdown + runtime metrics on
               its own; no extra code needed.
  * LOGS     — it prints ECS-JSON logs to stdout enriched with the current
               `trace.id` / `transaction.id`, so once the Elastic Agent (or
               Filebeat) collects them, Kibana can correlate log ↔ trace.

A background load generator hits the endpoints continuously, so you get a
steady stream of correlated data without running curl yourself.

Everything is configured from environment variables (see compose.demo.yaml).
"""
import logging
import os
import random
import sys
import threading
import time

import ecs_logging
import elasticapm
import requests
from elasticapm.contrib.flask import ElasticAPM
from elasticapm.handlers.logging import LoggingFilter
from flask import Flask, jsonify

# --- Configuration (all overridable via environment) -------------------------
SERVICE_NAME = os.getenv("ELASTIC_APM_SERVICE_NAME", "python-error-simulator")
PORT = int(os.getenv("PORT", "8000"))
ERROR_RATE = float(os.getenv("ERROR_RATE", "0.25"))      # 0..1, base failure odds
LOAD_INTERVAL = float(os.getenv("LOAD_INTERVAL", "1.0"))  # ~seconds between calls

# --- Logging: ECS JSON to stdout, enriched with APM trace IDs ----------------
# LoggingFilter stamps each record with elasticapm_{trace,transaction,span}_id;
# ecs_logging.StdlibFormatter maps those to ECS trace.id / transaction.id / ...
# That mapping is exactly what lets Kibana line logs up with their trace.
_handler = logging.StreamHandler(sys.stdout)
_handler.setFormatter(ecs_logging.StdlibFormatter())
_handler.addFilter(LoggingFilter())
logging.basicConfig(level=logging.INFO, handlers=[_handler], force=True)
log = logging.getLogger(SERVICE_NAME)
# Werkzeug's per-request access line is noise; we emit our own structured events.
logging.getLogger("werkzeug").setLevel(logging.WARNING)

# --- Flask app + Elastic APM agent -------------------------------------------
app = Flask(__name__)
app.config["ELASTIC_APM"] = {
    "SERVICE_NAME": SERVICE_NAME,
    "SERVER_URL": os.getenv("ELASTIC_APM_SERVER_URL", "http://apm-server:8200"),
    "SECRET_TOKEN": os.getenv("ELASTIC_APM_SECRET_TOKEN", "changeme_apm_token"),
    "ENVIRONMENT": os.getenv("ELASTIC_APM_ENVIRONMENT", "demo"),
    "SERVICE_VERSION": os.getenv("ELASTIC_APM_SERVICE_VERSION", "1.0.0"),
    # We format ECS logs ourselves above, so leave the agent's reformatter off.
    "LOG_ECS_REFORMATTING": "off",
}
apm = ElasticAPM(app)


class PaymentDeclined(Exception):
    """Simulated downstream payment failure."""


PRODUCTS = ["widget", "gadget", "gizmo", "doohickey", "thingamajig"]


def fake_db_query(label, lo=0.01, hi=0.08):
    """Simulate a database call as an APM span."""
    with elasticapm.capture_span(label, span_type="db", span_subtype="postgresql"):
        time.sleep(random.uniform(lo, hi))


def maybe_fail():
    """Raise a random exception ERROR_RATE of the time (captured by APM)."""
    if random.random() < ERROR_RATE:
        raise random.choice(
            [
                ValueError("invalid product id"),
                RuntimeError("inventory service unavailable"),
                PaymentDeclined("card declined by issuer"),
                TimeoutError("upstream timed out"),
            ]
        )


@app.get("/")
def health():
    return jsonify(status="ok", service=SERVICE_NAME)


@app.get("/products")
def products():
    fake_db_query("SELECT * FROM products")
    log.info("listed products", extra={"product_count": len(PRODUCTS)})
    maybe_fail()
    return jsonify(products=PRODUCTS)


@app.get("/users/<int:user_id>")
def get_user(user_id):
    with elasticapm.capture_span("cache.get", span_type="cache", span_subtype="redis"):
        time.sleep(random.uniform(0.001, 0.01))
    fake_db_query("SELECT * FROM users WHERE id = %s")
    if user_id % 7 == 0:
        log.warning("user not found", extra={"user_id": user_id})
        return jsonify(error="not found"), 404
    maybe_fail()
    return jsonify(user={"id": user_id, "name": f"user-{user_id}"})


@app.route("/checkout", methods=["GET", "POST"])
def checkout():
    item = random.choice(PRODUCTS)
    fake_db_query("BEGIN; SELECT stock FROM inventory ...")
    with elasticapm.capture_span("payment.charge", span_type="external", span_subtype="http"):
        time.sleep(random.uniform(0.05, 0.2))
        # Payment is the flaky bit — fails a bit more often than the rest.
        if random.random() < ERROR_RATE * 1.5:
            log.error("payment failed", extra={"order_item": item})
            raise PaymentDeclined(f"payment declined for {item}")
    fake_db_query("INSERT INTO orders ...")
    log.info("checkout complete", extra={"order_item": item})
    return jsonify(status="confirmed", item=item)


@app.get("/slow")
def slow():
    delay = random.uniform(0.5, 2.0)
    with elasticapm.capture_span("report.generate", span_type="app"):
        time.sleep(delay)
    log.info("slow report generated", extra={"duration_s": round(delay, 2)})
    return jsonify(status="done", took_s=round(delay, 2))


# --- Background load generator -----------------------------------------------
def load_generator():
    """Continuously hit our own endpoints so data flows with no manual curl."""
    base = f"http://127.0.0.1:{PORT}"
    paths = ["/products", "/checkout", "/slow", "/users/3", "/users/7", "/users/14", "/"]
    time.sleep(3)  # give the server a moment to come up
    log.info("load generator started", extra={"target": base, "interval_s": LOAD_INTERVAL})
    while True:
        path = random.choice(paths)
        try:
            requests.get(base + path, timeout=5)
        except requests.RequestException:
            pass  # 5xx from simulated errors are expected; APM already captured them
        time.sleep(max(0.05, random.uniform(0.5, 1.5) * LOAD_INTERVAL))


def start_load_generator():
    if os.getenv("ENABLE_LOAD_GENERATOR", "true").lower() in ("1", "true", "yes"):
        threading.Thread(target=load_generator, name="load-generator", daemon=True).start()


if __name__ == "__main__":
    log.info("starting service", extra={"port": PORT, "error_rate": ERROR_RATE})
    start_load_generator()
    # threaded=True  -> serve the load generator's requests concurrently
    # use_reloader=False -> stay single-process (one APM client, one generator)
    app.run(host="0.0.0.0", port=PORT, threaded=True, use_reloader=False, debug=False)
