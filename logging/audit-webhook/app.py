"""
Minimal logging/SIEM-style receiver for MinIO audit + server log webhooks.

MinIO POSTs one JSON audit event per S3 API call to /minio/audit, and
console/error log lines to /minio/logs. Events are appended as JSON Lines
to disk (append-only) and can be queried back over HTTP for the security
tests and for manual audit-log review.
"""
import json
import os
import threading
from datetime import datetime, timezone

from flask import Flask, jsonify, request

app = Flask(__name__)

DEFAULT_LOG_DIR = os.path.join(os.path.dirname(__file__), "logs")
LOG_DIR = os.environ.get("LOG_DIR", DEFAULT_LOG_DIR)
os.makedirs(LOG_DIR, exist_ok=True)
AUDIT_LOG_PATH = os.path.join(LOG_DIR, "audit.log")
SERVER_LOG_PATH = os.path.join(LOG_DIR, "server.log")

_lock = threading.Lock()


def _append(path: str, record: dict) -> None:
    record.setdefault("_received_at", datetime.now(timezone.utc).isoformat())
    with _lock:
        with open(path, "a") as f:
            f.write(json.dumps(record) + "\n")


@app.post("/minio/audit")
def receive_audit():
    payload = request.get_json(force=True, silent=True) or {"raw": request.get_data(as_text=True)}
    _append(AUDIT_LOG_PATH, payload)
    return "", 200


@app.post("/minio/logs")
def receive_server_log():
    payload = request.get_json(force=True, silent=True) or {"raw": request.get_data(as_text=True)}
    _append(SERVER_LOG_PATH, payload)
    return "", 200


def _tail_json_lines(path: str, limit: int) -> list:
    if not os.path.exists(path):
        return []
    with open(path) as f:
        lines = f.readlines()
    out = []
    for line in lines[-limit:]:
        line = line.strip()
        if not line:
            continue
        try:
            out.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return out


@app.get("/")
def index():
    return jsonify({"status": "ok", "endpoints": ["/events", "/healthz"]})


@app.get("/events")
def list_events():
    """Query audit events. Filters: ?limit=N&status_code=403&api=PutObject&user=alice&bucket=hr-documents"""
    limit = int(request.args.get("limit", 100))
    status_code = request.args.get("status_code")
    api = request.args.get("api")
    user = request.args.get("user")
    bucket = request.args.get("bucket")

    events = _tail_json_lines(AUDIT_LOG_PATH, limit=10000)

    def match(ev: dict) -> bool:
        api_details = ev.get("api", {}) if isinstance(ev.get("api"), dict) else {}
        if status_code and str(api_details.get("statusCode", ev.get("statusCode"))) != str(status_code):
            return False
        if api and api_details.get("name") != api:
            return False
        if user and ev.get("requestUser") != user and ev.get("accessKey") != user:
            return False
        if bucket and api_details.get("bucket") != bucket and ev.get("bucket") != bucket:
            return False
        return True

    filtered = [e for e in events if match(e)]
    return jsonify(filtered[-limit:])


@app.get("/healthz")
def healthz():
    return jsonify({"status": "ok"})


if __name__ == "__main__":
    host = os.environ.get("AUDIT_WEBHOOK_HOST", "0.0.0.0")
    port = int(os.environ.get("AUDIT_WEBHOOK_PORT", 8080))
    app.run(host=host, port=port)
