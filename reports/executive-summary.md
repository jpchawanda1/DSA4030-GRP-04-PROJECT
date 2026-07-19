# Executive Summary

**Client scenario:** A company stores documents in a cloud object storage
platform and needs assurance that access is authenticated, permissions are
role-appropriate, data is protected at rest and in transit, tampering is
detectable, activity is auditable, and data can be recovered after loss.

**What we built:** A self-hosted, Docker-orchestrated object storage
environment using MinIO (S3-compatible), OpenSSL (TLS certificate issuance),
and ClamAV (malware scanning), populated with 120,000 synthetic company
documents (HR records, finance invoices, contracts) generated with Faker.
Access is enforced by four role-scoped IAM identities across three
department buckets, all traffic is TLS-only, all objects are encrypted at
rest (SSE-S3/AES-256) and versioned, and every S3 API call — successful or
denied — is captured by a custom audit-log receiver.

**Testing performed:** Eight security tests covering unauthorized access,
role-based access control, TLS enforcement, encryption at rest, integrity/
tamper detection, audit log review, malware scanning, and backup & recovery.
**All eight passed** (see `reports/testing-matrix.md` for full evidence).
Notably, MinIO's internal bitrot protection independently caught a
deliberately corrupted object and refused to serve it, even without relying
on our external SHA-256 manifest.

**Key findings:** The core security controls held under adversarial testing —
cross-department access, anonymous access, and tampered data were all
correctly rejected or detected. The main residual risks are operational
rather than architectural: the TLS certificate is self-signed (not yet
CA-trusted), the encryption key is a single static value rather than a
rotated external KMS key, and malware scanning runs on-demand rather than
blocking uploads in real time.

**Recommendation:** The control set is sound for a pilot/internal
deployment. Before production use, replace the self-signed certificate with
a CA-issued one, move to an external KMS with key rotation, wire ClamAV into
MinIO's bucket-event notifications to scan synchronously on upload, and ship
audit logs to a durable SIEM with a defined retention policy. Full detail in
`reports/risk-assessment.md` and `reports/conclusion-recommendations.md`.
