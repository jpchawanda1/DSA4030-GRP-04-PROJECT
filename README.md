# DSA 4030 — Group 4: Secure Cloud Storage

A working, Dockerized secure object-storage environment for the "company stores
documents in a cloud object storage platform" scenario, built on **MinIO**,
**Docker**, and **OpenSSL**.

## What's here

| Part | Requirement | Where |
|---|---|---|
| A | Environment setup (data source, storage, security tools, logging) | `docker-compose.yml`, `dataset/`, `minio/`, `logging/audit-webhook/` |
| B | Dataset ≥100,000 records | `dataset/generate_dataset.py` (120,000 synthetic company documents) |
| C | Security controls (auth, RBAC, encryption, integrity, logging, malware scanning, backup) | `minio/init/`, `scripts/gen_certs.sh`, `logging/` |
| D | ≥6 security tests with evidence | `security-tests/` (8 tests, all passing) → results in `reports/testing-matrix.md` |
| E | Recommendations | `reports/conclusion-recommendations.md`, `reports/risk-assessment.md` |

Common deliverables checklist (see `reports/` for each):

| # | Deliverable | File |
|---|---|---|
| 1 | Executive Summary | `reports/executive-summary.md` |
| 2 | System Architecture Diagram | `reports/architecture.md` |
| 3 | Implementation Report | `reports/implementation-report.md` |
| 4 | Security Testing Matrix (≥6 tests) | `reports/testing-matrix.md` |
| 5 | Evidence Portfolio | `evidence/` (see `evidence/README.md` for the index) |
| 6 | Risk Assessment Table | `reports/risk-assessment.md` |
| 7 | Conclusion and Recommendations | `reports/conclusion-recommendations.md` |
| 8 | Appendices (source code, scripts, datasets, references) | `reports/appendices.md` |

Also required: **≥3 simulated security incidents** with detection/prevention
explained — see `reports/incident-simulations.md` (4 incidents + 1 bonus,
each mapped to a `security-tests/*.sh` script and its evidence file).

Common deliverables (executive summary, architecture, implementation report,
testing matrix, risk assessment, conclusion) are all drafted in `reports/` —
review and personalize before submission.

## Architecture

See [`reports/architecture.md`](reports/architecture.md) for the diagram and data flow.

In short: **MinIO** (TLS-only, SSE-S3 encrypted, versioned buckets) is the
storage platform; **OpenSSL** issues the CA + server certificate; **ClamAV**
provides malware scanning; a small **Flask webhook receiver** captures MinIO's
audit + server logs for review. Four RBAC users (`hr-manager`,
`finance-analyst`, `auditor`, `guest-contractor`) demonstrate role-based access
control across three document buckets (`hr-documents`, `finance-documents`,
`contracts-documents`) plus a `backups` bucket.

## Prerequisites

- Docker + Docker Compose v2
- Python 3.9+ (for the dataset generator, run on the host)
- OpenSSL (already on macOS/Linux by default)

## Quick start

```bash
bash scripts/setup.sh
```

This does everything in order: generates TLS certs, brings up MinIO/ClamAV/the
audit-webhook, initializes buckets + RBAC users + encryption + versioning,
generates the 120,000-record dataset, builds a SHA-256 integrity manifest, and
uploads the dataset into MinIO. Takes a few minutes on first run (Docker image
pulls + ClamAV virus-definition download).

Optional: pass a smaller record count while iterating, e.g. `bash scripts/setup.sh 5000`.

### Access

- MinIO Console: `https://localhost:9001` (self-signed cert — click through the
  browser warning, or trust `certs/ca.crt`). Login with `MINIO_ROOT_USER` /
  `MINIO_ROOT_PASSWORD` from `.env`.
- MinIO API: `https://localhost:9000`
- Audit log query API: `http://localhost:8080/events`

RBAC test user credentials are in `.env` (copied from `.env.example` on first
run — **change the placeholder passwords** if you intend to share this
environment beyond your own machine).

## Running the security tests

```bash
bash security-tests/run_all_tests.sh
```

Runs all 8 tests in order and writes:
- one timestamped evidence log per test to `evidence/`
- a run summary to `evidence/test_summary_<timestamp>.md`

Run an individual test with `bash security-tests/test_03_tls_enforcement.sh`, etc.

Results are already compiled in [`reports/testing-matrix.md`](reports/testing-matrix.md)
from the latest run — re-run and update it if you change anything.

## Tearing down / resetting

```bash
docker compose down            # stop containers, keep data
docker compose down -v         # stop containers AND wipe MinIO/ClamAV volumes (full reset)
```

To regenerate the dataset deterministically: `python3 dataset/generate_dataset.py --seed 42`
(same seed always produces the same records).

## Notes for the report / presentation

- **Why these tools**: MinIO is a self-hostable, S3-API-compatible object store
  with built-in IAM, encryption, versioning, and audit logging — it maps
  directly onto the "cloud object storage" scenario without needing a real
  cloud account. OpenSSL is the standard for issuing TLS certs and doing
  manual crypto operations. ClamAV is a widely used open-source AV engine,
  satisfying the "malware scanning" control.
- **Known limitations** (worth raising live): the TLS certificate is
  self-signed (a production deployment would use a CA-signed cert); the KMS
  key for SSE-S3 is a single static key rather than an external KMS with
  rotation; ClamAV here scans on-demand rather than blocking uploads in
  real time (a production setup would wire it into MinIO's bucket-event
  notifications to reject infected uploads synchronously).
- Each group member should personally run and be able to explain at least one
  security test end-to-end during the live demo — the `security-tests/test_0N_*.sh`
  scripts are self-contained and a good unit to divide up.
