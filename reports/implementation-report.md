# Implementation Report

## 1. Overview

The environment implements the "Secure Cloud Storage" scenario end-to-end
using three open-source components orchestrated by Docker Compose:

- **MinIO** (`minio/minio:RELEASE.2025-04-22T22-12-26Z`) — the object storage
  platform. Chosen because it is S3-API-compatible, self-hostable, and ships
  with IAM/RBAC, server-side encryption, versioning, and audit-log webhooks
  built in — it lets us demonstrate every required control without needing a
  real cloud account.
- **OpenSSL** — issues a private root CA and a server certificate for MinIO,
  used to enforce TLS-only access.
- **ClamAV** (`clamav/clamav:1.4`) — open-source antivirus engine, used for
  the malware-scanning control.

A supporting Flask service (`logging/audit-webhook/`) receives MinIO's audit
and server-log webhook events and persists them as append-only JSON Lines,
exposing a query API for log review.

See `reports/architecture.md` for the component diagram and data flow.

## 2. TLS setup (`scripts/gen_certs.sh`)

`scripts/gen_certs.sh` generates a 4096-bit RSA root CA (`certs/ca.crt` /
`ca.key`) and a 2048-bit RSA server key/certificate (`certs/public.crt` /
`private.key`) signed by that CA, with SANs for `localhost`, `minio`, and
`127.0.0.1`. MinIO auto-detects `public.crt`/`private.key` in its configured
`--certs-dir` and switches to HTTPS-only for both the S3 API (port 9000) and
the web console (port 9001). Validity: 825 days.

## 3. Storage platform configuration (`minio/init/init-minio.sh`)

Run once via `docker compose run --rm --entrypoint /bin/sh mc /minio/init/init-minio.sh`:

- **Buckets:** `hr-documents`, `finance-documents`, `contracts-documents`,
  plus `backups` (created with `--with-lock` for object-lock support).
- **Versioning:** enabled on all four buckets (`mc version enable`) —
  underpins both the integrity test (bitrot-protected reads) and the
  backup/recovery test (restore a prior version).
- **Encryption:** default bucket encryption set to `sse-s3` (`mc encrypt
  set sse-s3`) on all four buckets. The KMS key is supplied via the
  `MINIO_KMS_SECRET_KEY` environment variable (a single static 32-byte key,
  generated with `openssl rand -base64 32`) — MinIO's built-in single-key KMS
  mode, sufficient for this lab but not for production (see recommendations).
- **IAM policies:** three custom policies in `minio/policies/` —
  `hr-readwrite` (RW on `hr-documents` only), `finance-readonly` (RO on
  `finance-documents` only), `auditor-readonly` (RO across all three document
  buckets).
- **Users:** four accounts — `hr-manager` (hr-readwrite),
  `finance-analyst` (finance-readonly), `auditor` (auditor-readonly), and
  `guest-contractor` (created with **no** policy attached, so it is an
  authenticated identity with zero authorized actions — used to distinguish
  "authentication succeeds, authorization fails" from "authentication
  fails" in testing).

## 4. Dataset (`dataset/`)

`dataset/generate_dataset.py` uses Faker (seeded, `--seed 42`, deterministic)
to generate three document categories, one per bucket:

- `hr-documents`: employee records (name, national ID, salary, department, etc.)
- `finance-documents`: vendor invoices (amount, currency, due date, account number, etc.)
- `contracts-documents`: client contracts (contract type, value, signatory, terms summary, etc.)

Default run: 40,000 records × 3 categories = **120,000 records**, exceeding
the 100,000 minimum. Records are written as newline-delimited JSON, sharded
into files of 2,000 records each (20 shard files per bucket) rather than one
object per record — this mirrors how a real company would batch-export
documents into cloud storage rather than making 120,000 individual API
calls, while keeping upload time and object count manageable.

`dataset/build_manifest.py` computes a SHA-256 hash of every shard file
before upload and writes `dataset/output/manifest.sha256.json` — this is the
integrity baseline used by the integrity-verification test.

`minio/init/upload_dataset.sh` mirrors each category directory into its
matching bucket with `mc mirror`.

## 5. Logging (`logging/audit-webhook/`)

MinIO is configured (via `MINIO_AUDIT_WEBHOOK_*` / `MINIO_LOGGER_WEBHOOK_*`
environment variables in `docker-compose.yml`) to POST one JSON audit event
per S3 API call, and server/error log lines, to a small Flask app. The app
appends each event as a JSON line to `logging/audit-webhook/logs/audit.log`
/ `server.log` and exposes `GET /events` with filters (`user`, `api`,
`status_code`, `bucket`, `limit`) for log review — this is what the
audit-log-review security test and any manual investigation query against.

## 6. Malware scanning (ClamAV)

ClamAV runs as its own container with the official virus database baked
into the image (`main.cvd`) plus `daily.cld` fetched on startup. It is used
on-demand via `clamdscan` against files mounted read-only from
`security-tests/malware-samples/` and `dataset/output/`. Note: on Apple
Silicon hosts, `clamav/clamav:1.4` has no arm64 image, so the compose
service pins `platform: linux/amd64` and runs under emulation.

## 7. Orchestration

`scripts/setup.sh` runs the full bootstrap in order: cert generation → `.env`
setup → `docker compose up` (MinIO, audit-webhook, ClamAV) → wait for MinIO
healthcheck → `init-minio.sh` → dataset generation + manifest → dataset
upload. `security-tests/run_all_tests.sh` then runs all eight tests and
writes a timestamped summary plus one evidence log per test to `evidence/`.

## 8. Limitations encountered

- The self-signed CA requires `--insecure`/manual trust for `mc` and
  browser access — acceptable for a lab, not for production.
- No external secrets manager; root/user passwords live in `.env`
  (gitignored, not committed).
- ClamAV's on-demand scanning (via `clamdscan` in the test) is not wired
  into the upload path itself — a real deployment would use MinIO bucket
  notifications to trigger a scan-then-quarantine step synchronously.
