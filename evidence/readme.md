# Evidence Portfolio Index (Part D / Common Deliverable #5)

This folder is the evidence portfolio: raw terminal output, logs, and
dashboard/API captures backing every claim in `reports/testing-matrix.md`,
`reports/incident-simulations.md`, and `reports/risk-assessment.md`.

## How to read this folder

| Category | Files | What it proves |
|---|---|---|
| **Terminal output / test logs** | `test0{1..8}_*_<timestamp>.log` | Full command-by-command transcript of each security test (Objective/Procedure/Expected/Actual sections, per `security-tests/common.sh`'s `start_evidence` helper) |
| **Run summaries** | `test_summary_<timestamp>.md` | Pass/fail roll-up for a full `run_all_tests.sh` execution |
| **Audit/monitoring dashboard captures** | `audit_allowed_events.json`, `audit_allowed_events.pretty.json`, `audit_denied_events.json`, `audit_denied_events.pretty.json` | Raw JSON exported from the audit-webhook's `GET /events` query API (the "monitor activity" control) — allowed vs. denied API calls, queryable by user/status/bucket |
| **Integrity artifacts** | `baseline_download.jsonl`, `post_tamper_download.jsonl`, `post_tamper_error.txt` | Before/after state of the object used in the integrity-verification test — baseline content, the (empty/failed) post-tamper read, and the error MinIO returned when the corrupted object was requested |
| **Access control artifacts** | `rbac_write_test.json` | Evidence of a denied write attempt by a read-only RBAC identity |
| **Configuration files** | see `reports/appendices.md`, Appendix C | `docker-compose.yml`, `minio/policies/*.json`, `.env.example`, `certs/ca.crt` / `certs/public.crt` are the config-file evidence, kept at the repo root rather than duplicated here |

## Screenshots (`evidence/screenshots/`)

Captured 2026-07-20 against the live running environment (`docker compose ps`
showed MinIO, ClamAV, and audit-webhook all healthy at capture time). Taken
with a headless Chromium (Playwright) configured to trust the project's
self-signed CA, since a normal browser's cert-warning interstitial can't be
clicked through by automation — see "Screenshots / live dashboard views"
below for how to reproduce these manually during the live demo.

| # | File | Shows |
|---|---|---|
| 1 | `00_console_login.png` | MinIO Console login page over HTTPS (TLS enforced) |
| 2 | `01_admin_landing.png`, `02_admin_object_browser_buckets.png` | Admin Object Browser — all 4 buckets (`hr-documents`, `finance-documents`, `contracts-documents`, `backups`) |
| 3 | `03_admin_bucket_contracts-documents_objects.png` | Object listing inside `contracts-documents` (20 uploaded shards) |
| 4 | `04_admin_buckets_admin_list.png` | Administrator → Buckets view with per-bucket usage/object counts/access |
| 5 | `05_admin_bucket_contracts-documents_summary.png` | Bucket summary detail pane |
| 6 | `06_admin_bucket_contracts-documents_encryption.png` | Bucket encryption tab — confirms SSE-S3 default encryption is enabled |
| 7 | `07_admin_bucket_contracts-documents_versioning.png` | Bucket versioning tab |
| 8 | `08_admin_policies_list.png` | IAM Policies list (`hr-readwrite`, `finance-readonly`, `auditor-readonly`, `consoleAdmin`) |
| 9–11 | `09_admin_policy_hr-readwrite_detail.png`, `10_admin_policy_finance-readonly_detail.png`, `11_admin_policy_auditor-readonly_detail.png` | Each RBAC policy's actual JSON statement (Effect/Actions/Resources) proving least-privilege scoping |
| 12 | `12_admin_identity_users_list.png` | Identity → Users list: `hr-manager`, `finance-analyst`, `auditor`, `guest-contractor` |
| 13 | `13_admin_identity_user_hr-manager_detail.png` | `hr-manager` user detail (attached policy) |
| 14 | `14_admin_monitoring_or_logs.png` | Monitoring → Logs live-tail panel |
| 15 | `15_hr-manager_object_browser.png` | `hr-manager` logged in — sees only `hr-documents` (R/W) |
| 16 | `16_hr-manager_denied_finance-documents.png` | `hr-manager` navigating directly to `finance-documents` → **Access Denied** banner |
| 17 | `17_finance-analyst_object_browser.png` | `finance-analyst` logged in — sees only `finance-documents`, **Access: R** (read-only, no write) |
| 18 | `18_finance-analyst_denied_hr-documents.png` | `finance-analyst` navigating directly to `hr-documents` → **Access Denied** |
| 19 | `19_auditor_object_browser_readonly_all.png` | `auditor` logged in — sees all 3 document buckets, all **Access: R** |
| 20 | `20_guest-contractor_object_browser_no_access.png` | `guest-contractor` logged in (auth succeeds) but sees **zero buckets** — authenticated identity with no authorization, per design |
| 21 | `21_admin_monitoring_metrics_dashboard.png` | Server metrics dashboard — buckets/objects/servers/drives/uptime |
| 22 | `22_admin_access_keys.png` | Access Keys management page |
| 23 | `23_admin_identity_groups.png` | Identity → Groups (empty — this project attaches policies directly to users) |
| 24 | `24_audit_webhook_events_all.png` | Audit-webhook `/events` dashboard — all logged S3 API calls |
| 25 | `25_audit_webhook_events_hr-manager.png` | `/events?user=hr-manager` — filtered activity monitoring for one identity |
| 26 | `26_audit_webhook_events_finance-analyst_denied.png` | `/events?user=finance-analyst&status_code=403` — captures the live cross-bucket denial generated while taking screenshots 16/18, proving denied actions are logged in real time |
| 27 | `27_audit_webhook_root.png` | Audit-webhook service root endpoint |
| 28 | `29_audit_webhook_events_tamper_503_detected.png` | **Live incident capture (2026-07-20):** `contracts_shard_0003.jsonl` was deliberately corrupted on the MinIO backend volume (same technique as `test_05_integrity_verification.sh`) while this dashboard was being screenshotted. The resulting `GetObject` calls show `"status": "Service Unavailable", "statusCode": 503"` — MinIO's internal bitrot/checksum protection rejecting the tampered read, captured and queryable in real time. The object was restored immediately afterward from `dataset/output/` and re-verified byte-for-byte against `manifest.sha256.json` (SHA-256 `96da0db9...` matched exactly) — no data was left corrupted. |

**Note on the MinIO Console's own "Logs" / "Audit" panels:** `14_admin_monitoring_or_logs.png` (Console → Monitoring → Logs) intentionally shows "No logs to display" even during the live tamper test above — that panel only streams MinIO's internal server/application log lines (startup, panics, warnings), not per-request S3 protocol responses, so 403/404/503 results never appear there. The Console's "Audit" panel likewise reports "not available" because it requires configuring a separate Log Search (Postgres-backed) target; this project deliberately uses the custom Flask `audit-webhook` (captured above) as its monitoring/audit solution instead, per `reports/architecture.md` and `reports/implementation-report.md`.

## Screenshots / live dashboard views

Two UIs are available for live, visual evidence during the demo/presentation:

1. **MinIO Console** — `https://localhost:9001` (login with `MINIO_ROOT_USER`
   / `MINIO_ROOT_PASSWORD` from `.env`). Shows buckets, versioning status,
   encryption status, and IAM users/policies visually. The console uses the
   project's self-signed certificate (`certs/ca.crt`), so a browser will show
   a certificate warning — click through it (or import `certs/ca.crt` as a
   trusted CA beforehand) to reach the login page. This click-through step
   itself is worth showing live, since it demonstrates the TLS-only
   enforcement described in `reports/testing-matrix.md` (test 3).
2. **Audit log query API** — `http://localhost:8080/events` (plain HTTP,
   no cert warning) — JSON view of every logged S3 call; add `?user=`,
   `?api=`, `?status_code=`, or `?bucket=` query params to filter live.
   The static `.json`/`.pretty.json` files in this folder are point-in-time
   exports of this same endpoint.

Per the assignment rules, screenshots/logs alone are not sufficient —
**live demonstration is mandatory** — so these two URLs are what each group
member should drive during their assigned portion of the live demo rather
than relying solely on the static captures in this folder.
