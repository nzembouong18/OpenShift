"""vote-app : API de vote minimale (Flask + PostgreSQL) — fil rouge de la formation OpenShift.

Endpoints : POST /api/vote {"choice": "a|b"} · GET /api/results · GET /healthz · GET /readyz · GET /metrics
Configuration par variables d'environnement (ConfigMap/Secret) : DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD.
"""
import os
import time

from flask import Flask, Response, jsonify, request

try:  # la base n'est requise que pour /readyz, /api/*
    import psycopg2
except ImportError:  # pragma: no cover - permet d'exécuter les tests sans driver
    psycopg2 = None

app = Flask(__name__)

CHOICES = ("a", "b")
_requests = {}


def _db():
    return psycopg2.connect(
        host=os.environ.get("DB_HOST", "postgres"),
        port=int(os.environ.get("DB_PORT", "5432")),
        dbname=os.environ.get("DB_NAME", "vote"),
        user=os.environ.get("DB_USER", "app"),
        password=os.environ.get("DB_PASSWORD", ""),
        connect_timeout=3,
    )


def _init_schema(conn):
    with conn, conn.cursor() as cur:
        cur.execute("CREATE TABLE IF NOT EXISTS votes (choice text PRIMARY KEY, n bigint NOT NULL DEFAULT 0)")
        for c in CHOICES:
            cur.execute("INSERT INTO votes (choice, n) VALUES (%s, 0) ON CONFLICT DO NOTHING", (c,))


def _count(path, status):
    _requests[(path, str(status))] = _requests.get((path, str(status)), 0) + 1


@app.after_request
def _metrics(resp):
    _count(request.path if request.url_rule else "other", resp.status_code)
    return resp


@app.get("/healthz")
def healthz():
    return jsonify(status="ok")


@app.get("/readyz")
def readyz():
    try:
        conn = _db()
        _init_schema(conn)
        conn.close()
        return jsonify(status="ready")
    except Exception as exc:  # noqa: BLE001
        return jsonify(status="not-ready", error=str(exc)), 503


@app.post("/api/vote")
def vote():
    payload = request.get_json(silent=True) or {}
    choice = payload.get("choice")
    if choice not in CHOICES:
        return jsonify(error="choice doit valoir 'a' ou 'b'"), 400
    conn = _db()
    try:
        with conn, conn.cursor() as cur:
            cur.execute("UPDATE votes SET n = n + 1 WHERE choice = %s", (choice,))
    finally:
        conn.close()
    return jsonify(status="recorded", choice=choice), 201


@app.get("/api/results")
def results():
    conn = _db()
    try:
        with conn, conn.cursor() as cur:
            cur.execute("SELECT choice, n FROM votes ORDER BY choice")
            rows = dict(cur.fetchall())
    finally:
        conn.close()
    return jsonify({c: int(rows.get(c, 0)) for c in CHOICES})


@app.get("/metrics")
def metrics():
    lines = ["# TYPE http_requests_total counter"]
    for (path, status), n in sorted(_requests.items()):
        lines.append(f'http_requests_total{{path="{path}",status="{status}"}} {n}')
    lines.append("# TYPE process_start_time_seconds gauge")
    lines.append(f"process_start_time_seconds {START}")
    return Response("\n".join(lines) + "\n", mimetype="text/plain")


START = int(time.time())

if __name__ == "__main__":  # exécution locale uniquement
    app.run(host="0.0.0.0", port=8080)
