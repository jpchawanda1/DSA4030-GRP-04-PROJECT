# Simulated Security Incidents

The brief requires demonstrating **at least three simulated security incidents**
and explaining how the environment's controls detect or prevent them. The
`security-tests/` scripts (Part D) already execute these attacks; this
document reframes four of them explicitly as incident scenarios — what an
attacker/insider would actually be trying to do, and which control caught it.

## Incident 1 — External attacker attempts to read documents without credentials

**Scenario:** An outsider discovers the storage endpoint (e.g. via port scan
or a leaked URL) and tries to list/download objects with no credentials and
with a guessed/invalid access key — the classic "found an open bucket"
data-breach pattern.

**Simulated by:** `security-tests/test_01_unauthorized_access.sh`

**Detection/Prevention:**
- MinIO's default-deny bucket policy rejects any request that isn't signed
  with a valid access key — there is no anonymous/public read policy on any
  bucket.
- An anonymous `curl` GET returned **HTTP 403 `AccessDenied`**; `mc` with a
  bogus key failed at alias creation ("Access Key Id... does not exist").
- Every attempt (successful or not) is captured by the audit-webhook
  receiver with the source IP, requested path, and 403 status — so even a
  blocked attempt leaves a forensic trail for detection/alerting.

**Evidence:** `evidence/test01_unauthorized_access_20260711T140449Z.log`

## Incident 2 — Insider / compromised account attempts cross-department access

**Scenario:** A legitimate but lower-privileged account (e.g. an HR
manager's credentials, phished or misused) is used to try to read the
Finance department's invoices, and a read-only Finance account attempts to
modify data it shouldn't be able to write — representative of insider
threat or lateral movement after a single account is compromised.

**Simulated by:** `security-tests/test_02_rbac_enforcement.sh`

**Detection/Prevention:**
- Role-scoped IAM policies (`hr-readwrite`, `finance-readonly`,
  `auditor-readonly`) enforce least privilege per bucket; `hr-manager` has
  no grant on `finance-documents` and vice versa.
- `hr-manager` → `finance-documents`: **Access Denied**. `finance-analyst`
  → write attempt: **Insufficient permissions**. `guest-contractor`
  (authenticated, no policy attached) → denied on every bucket.
- Positive controls confirmed each account *can* still do its legitimate
  job (read its own bucket), proving the denial is policy-driven, not a
  broken connection.
- Denied attempts are logged with `statusCode: 403` and the acting
  `accessKey`, enabling detection of repeated cross-boundary attempts
  (a signal of a compromised or misused credential).

**Evidence:** `evidence/test02_rbac_enforcement_20260711T140451Z.log`

## Incident 3 — Data tampering / integrity attack on stored documents

**Scenario:** An attacker with backend/disk access (or a bug elsewhere in
the storage stack) corrupts the bytes of a stored document directly on
disk — analogous to on-disk tampering, bitrot, or a ransomware-style
corruption attempt — trying to alter records without detection.

**Simulated by:** `security-tests/test_05_integrity_verification.sh`

**Detection/Prevention:**
- A pre-upload SHA-256 manifest (`dataset/output/manifest.sha256.json`)
  gives an independent, external integrity baseline.
- The object's on-disk backend file was directly corrupted with `dd`.
  MinIO's own internal bitrot/checksum protection detected the corruption
  and refused to serve the tampered object (`mc cat` failed rather than
  silently returning altered data) — this is a defense-in-depth win: the
  storage platform itself caught the tampering before our external hash
  check was even needed.
- Recovery: the object was restored from the original source shard and
  re-verified hash-for-hash against the manifest, confirming the tampering
  was both detected and reversible.

**Evidence:** `evidence/test05_integrity_verification_20260711T140501Z.log`;
re-verified live on 2026-07-20 against a second object
(`contracts_shard_0003.jsonl`) with the resulting `GetObject` → `503 Service
Unavailable` calls captured by the audit-webhook dashboard — see
`evidence/screenshots/29_audit_webhook_events_tamper_503_detected.png` and
`evidence/README.md`.

## Incident 4 — Malicious file uploaded to shared storage

**Scenario:** A user (malicious insider or an unwittingly compromised
workstation) uploads a malware-laden file into a shared document bucket,
where it could later be downloaded by other departments or auditors.

**Simulated by:** `security-tests/test_07_malware_scanning.sh` (using the
industry-standard EICAR test file, which is byte-for-byte recognized by
every AV engine as "malware" without being actual malicious code)

**Detection/Prevention:**
- ClamAV (`clamdscan`) scanned the EICAR file, a clean control document,
  and a real dataset shard.
- EICAR file → **`Eicar-Signature FOUND`**, non-zero exit code. Clean
  sample and dataset shard → **`OK`**, exit 0 — confirming no false
  positives on legitimate documents.
- **Known limitation** (also flagged in `reports/conclusion-recommendations.md`):
  scanning here is on-demand rather than wired into the upload path via
  MinIO bucket-event notifications, so a real deployment should scan
  synchronously and quarantine on `PutObject` rather than after the fact.

**Evidence:** `evidence/test07_malware_scanning_20260711T140514Z.log`

## Bonus incident — Accidental/malicious deletion of a document

**Scenario:** A user (or attacker with write access) deletes a document,
either by mistake or to destroy evidence.

**Simulated by:** `security-tests/test_08_backup_recovery.sh`

**Detection/Prevention:** Bucket versioning turns a delete into a
recoverable delete-marker rather than permanent data loss; a secondary
mirrored `backups` bucket provides an independent recovery path. The
object was unreadable immediately after deletion, then fully restored via
both mechanisms with a matching SHA-256 hash.

**Evidence:** `evidence/test08_backup_recovery_20260711T140514Z.log`

---

**Summary:** four incidents beyond the two required for the minimum (three)
were exercised, spanning unauthorized external access, insider/RBAC
violation, integrity tampering, and malware upload — plus a bonus
deletion/recovery scenario. Every incident was either **prevented** (denied
before completing) or **detected and remediated** (tampering, deletion),
with the specific control responsible identified in each case above.
