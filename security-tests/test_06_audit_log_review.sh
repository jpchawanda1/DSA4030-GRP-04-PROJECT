#!/usr/bin/env bash
# TEST 06 — Audit logging: every S3 call (allowed and denied) is captured and reviewable.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/common.sh"
start_evidence "test06_audit_log_review"

WEBHOOK="http://localhost:${AUDIT_WEBHOOK_PORT:-8080}"

log_section "OBJECTIVE"
echo "Confirm the logging pipeline (MinIO -> audit webhook -> logs/audit.log) captures"
echo "both a successful, authorized request and a denied, unauthorized request, and that"
echo "the log is reviewable via the query API (satisfies Part A 'logging capability' and"
echo "Part C 'review audit logs')."

log_section "PROCEDURE 1: Generate a known-good, attributable event (hr-manager reads own bucket)"
run_mc alias set hr-manager https://minio:9000 hr-manager "$HR_MANAGER_PASSWORD" --insecure >/dev/null
run_mc cat grp4/hr-documents/hr_shard_0001.jsonl --insecure > /dev/null || true

log_section "PROCEDURE 2: Generate a known-bad, attributable denied event (finance-analyst reads hr-documents)"
run_mc alias set finance-analyst https://minio:9000 finance-analyst "$FINANCE_ANALYST_PASSWORD" --insecure >/dev/null
run_mc ls finance-analyst/hr-documents --insecure || true

sleep 2

log_section "PROCEDURE 3: Query the audit log receiver for the ALLOWED event"
curl -s "$WEBHOOK/events?user=hr-manager&limit=20" > "$EVIDENCE_DIR/audit_allowed_events.json"
python3 -m json.tool < "$EVIDENCE_DIR/audit_allowed_events.json" > "$EVIDENCE_DIR/audit_allowed_events.pretty.json"
head -60 "$EVIDENCE_DIR/audit_allowed_events.pretty.json"

log_section "PROCEDURE 4: Query the audit log receiver for the DENIED event"
curl -s "$WEBHOOK/events?user=finance-analyst&limit=20" > "$EVIDENCE_DIR/audit_denied_events.json"
python3 -m json.tool < "$EVIDENCE_DIR/audit_denied_events.json" > "$EVIDENCE_DIR/audit_denied_events.pretty.json"
head -60 "$EVIDENCE_DIR/audit_denied_events.pretty.json"

log_section "PROCEDURE 5: Raw tail of the append-only audit log file (evidence of persistence)"
tail -n 10 "$ROOT_DIR/logging/audit-webhook/logs/audit.log" 2>/dev/null || echo "(log file not found on host mount)"

log_section "EXPECTED RESULT"
echo "Both queries return at least one matching JSON event including accessKey/requestUser,"
echo "API name, bucket, and status code, proving allowed and denied actions are both logged."

log_section "ACTUAL RESULT"
ALLOWED_COUNT=$(python3 -c "import json;print(len(json.load(open('$EVIDENCE_DIR/audit_allowed_events.json'))))" 2>/dev/null || echo 0)
DENIED_COUNT=$(python3 -c "import json;print(len(json.load(open('$EVIDENCE_DIR/audit_denied_events.json'))))" 2>/dev/null || echo 0)
echo "Matched allowed events: $ALLOWED_COUNT | Matched denied events: $DENIED_COUNT"
if [ "$ALLOWED_COUNT" -ge 1 ] && [ "$DENIED_COUNT" -ge 1 ]; then
  echo "PASS - audit trail captures both authorized and denied activity."
else
  echo "FAIL - one or both event types missing from the audit log."
fi
