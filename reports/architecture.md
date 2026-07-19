# System Architecture — Group 4: Secure Cloud Storage

```mermaid
flowchart TB
    subgraph Clients["Users (RBAC identities)"]
        A[hr-manager]
        F[finance-analyst]
        AU[auditor]
        G[guest-contractor - no policy]
        BAD[unauthorized / anonymous]
    end

    subgraph Docker["Docker network: storage-net"]
        MC["mc CLI\n(admin + test tool)"]
        MINIO["MinIO\nObject Storage\nTLS (OpenSSL cert)\nSSE-S3 encryption\nversioning + audit_webhook"]
        AUDIT["audit-webhook\n(Flask)\nreceives MinIO audit + server logs\nappends to audit.log / server.log"]
        CLAM["ClamAV\nmalware scanning"]
    end

    subgraph Buckets["MinIO Buckets"]
        B1[(hr-documents\nRW: hr-manager only)]
        B2[(finance-documents\nRO: finance-analyst)]
        B3[(contracts-documents\nRO: auditor)]
        B4[(backups\nobject-locked)]
    end

    A -- HTTPS --> MINIO
    F -- HTTPS --> MINIO
    AU -- HTTPS --> MINIO
    G -- HTTPS (denied) --> MINIO
    BAD -- HTTPS (denied) --> MINIO
    MC -- admin API --> MINIO
    MINIO --> B1
    MINIO --> B2
    MINIO --> B3
    MINIO --> B4
    MINIO -- audit + log events (webhook) --> AUDIT
    CLAM -. scans documents .-> Buckets

    subgraph Dataset["Part B: Dataset"]
        GEN["generate_dataset.py\n(Faker)\n120,000 synthetic company\ndocuments (HR/Finance/Contracts)"]
    end
    GEN -- mc mirror --> MINIO
```

## Components

| Layer | Component | Role |
|---|---|---|
| Data source | `dataset/generate_dataset.py` | Generates 120,000 synthetic company documents (HR records, finance invoices, contracts) with Faker |
| Storage platform | MinIO | S3-compatible object storage; TLS, SSE-S3 encryption, versioning, IAM/RBAC, audit webhook |
| Security tool #1 | OpenSSL | Issues the root CA + server certificate used for TLS; also usable for ad-hoc file encryption |
| Security tool #2 | ClamAV | Malware scanning of uploaded documents |
| Logging | `audit-webhook` (Flask) | Receives MinIO audit + server log events over HTTP, persists as JSON Lines, exposes a query API |
| Orchestration | Docker Compose | Wires all services on an isolated `storage-net` bridge network |

## Data flow

1. `scripts/gen_certs.sh` issues a root CA and MinIO server certificate (OpenSSL).
2. `docker compose up` starts MinIO (TLS-only), the audit-webhook receiver, and ClamAV.
3. `minio/init/init-minio.sh` creates buckets, enables versioning + SSE-S3 encryption, creates IAM policies and 4 RBAC users.
4. `dataset/generate_dataset.py` + `build_manifest.py` generate the dataset and a SHA-256 integrity manifest.
5. `minio/init/upload_dataset.sh` uploads the dataset into the matching buckets.
6. `security-tests/*.sh` exercise the environment (RBAC, TLS, encryption, integrity, logging, malware scanning, backup/recovery) and write evidence to `evidence/`.
