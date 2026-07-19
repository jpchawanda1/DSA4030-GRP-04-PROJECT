# Conclusion and Recommendations (Part E)

## Vulnerabilities identified

None of the eight security tests found a control that failed to enforce its
intended boundary — but the exercise of building and attacking the
environment surfaced several design-level weaknesses that wouldn't show up
as a "failed test" but matter for a real deployment:

1. **Self-signed TLS certificate.** Our OpenSSL CA is trusted only because we
   told every client to trust it (`--insecure` / manual CA import). In
   production this is a spoofing risk — any host can mimic that trust
   relationship if the CA key leaks.
2. **Static single-key encryption.** SSE-S3 here uses one long-lived KMS key
   baked into an environment variable, with no rotation and no access
   control on the key itself separate from MinIO's own access control. A
   compromise of the MinIO host compromises the key.
3. **Malware scanning is out-of-band.** ClamAV scans files we point it at,
   after the fact — it does not sit in the upload path. A malicious file
   could be stored (and even downloaded by another user) before anyone
   thinks to scan it.
4. **Root credentials in `.env`.** Convenient for a lab, but a single
   plaintext file holding the MinIO root password is a soft target; there is
   no secrets rotation or MFA.
5. **Single-node storage.** MinIO is running as one drive/one pool
   (`docker-compose.yml`), so there is no erasure-coding redundancy across
   nodes — a disk failure loses data unless the external `backups` bucket /
   mirror is current.

## Remaining risks

Even with the controls in place, some risk is accepted rather than
eliminated for this project's scope: insider risk from the root/admin
account (which bypasses all bucket-level RBAC by design), the audit log
receiver itself is a single point of failure with no redundancy or tamper-
evidence (an attacker with host access could edit `audit.log` after the
fact), and there's no network segmentation beyond the single Docker bridge
network — see `reports/risk-assessment.md` for the full table with
impact/likelihood ratings.

## Recommended improvements (for an enterprise deployment)

- **Certificates:** replace the self-signed CA with a certificate from a
  trusted internal PKI or public CA (e.g. via ACME/Let's Encrypt for
  internet-facing deployments).
- **Key management:** move from a static `MINIO_KMS_SECRET_KEY` to an
  external KMS (HashiCorp Vault, AWS KMS, or MinIO KES) with key rotation
  and separate access control from the storage layer itself.
- **Real-time malware scanning:** wire ClamAV into MinIO's bucket-event
  notifications (`mc event add`) so every `PutObject` triggers a scan before
  the object is considered "clean," with a quarantine bucket for hits.
- **Log durability and tamper evidence:** ship audit events from the webhook
  receiver to a dedicated log store (ELK, Loki, or a managed SIEM) with
  write-once retention, rather than a local JSON-lines file on the same host.
- **Secrets management:** move credentials out of `.env` into a secrets
  manager, and require MFA for the root/admin account.
- **High availability:** deploy MinIO as a multi-node, multi-drive cluster
  for erasure-coded redundancy, and schedule the mirror-based backup job
  (currently manual/on-demand in this project) as a recurring, monitored task.
- **Access review cadence:** periodically review the four RBAC identities
  and their attached policies (and any new ones added later) rather than
  treating the initial policy assignment as permanent.

## Lessons learned

Building this environment reinforced that the strongest evidence of a
control's effectiveness comes from adversarial testing, not configuration
review: e.g., encryption-at-rest "looks" configured via `mc encrypt info`,
but the meaningful proof was pulling the raw ciphertext bytes off the
backend volume and showing they're not the plaintext JSON. Similarly, the
integrity test showed that MinIO's own internal bitrot protection caught
tampering independently of our external SHA-256 manifest — a useful
reminder that some controls are already provided by the platform and don't
need to be re-implemented, only verified.
