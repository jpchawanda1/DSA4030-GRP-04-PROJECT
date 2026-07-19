#!/bin/sh
# Runs inside the `mc` container: docker compose run --rm mc /minio/init/init-minio.sh
# Idempotent bootstrap: buckets, versioning, default SSE-S3 encryption, IAM policies, users.
set -eu

ALIAS=grp4
ENDPOINT="https://minio:9000"

echo "[*] Configuring mc alias '$ALIAS' -> $ENDPOINT"
mc alias set "$ALIAS" "$ENDPOINT" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" --insecure
mc admin info "$ALIAS" --insecure >/dev/null

echo "[*] Creating buckets..."
for b in hr-documents finance-documents contracts-documents; do
  mc mb --insecure --ignore-existing "$ALIAS/$b"
done
mc mb --insecure --ignore-existing --with-lock "$ALIAS/backups"

echo "[*] Enabling versioning (integrity / recovery) on all buckets..."
for b in hr-documents finance-documents contracts-documents backups; do
  mc version enable --insecure "$ALIAS/$b"
done

echo "[*] Enabling default server-side encryption (SSE-S3, AES256) on all buckets..."
for b in hr-documents finance-documents contracts-documents backups; do
  mc encrypt set sse-s3 --insecure "$ALIAS/$b"
done

echo "[*] Creating IAM policies..."
mc admin policy create --insecure "$ALIAS" hr-readwrite /minio/policies/hr-readwrite-policy.json
mc admin policy create --insecure "$ALIAS" finance-readonly /minio/policies/finance-readonly-policy.json
mc admin policy create --insecure "$ALIAS" auditor-readonly /minio/policies/auditor-readonly-policy.json

echo "[*] Creating users (multi-user RBAC)..."
mc admin user add --insecure "$ALIAS" hr-manager "$HR_MANAGER_PASSWORD"
mc admin user add --insecure "$ALIAS" finance-analyst "$FINANCE_ANALYST_PASSWORD"
mc admin user add --insecure "$ALIAS" auditor "$AUDITOR_PASSWORD"
mc admin user add --insecure "$ALIAS" guest-contractor "$GUEST_PASSWORD"

echo "[*] Attaching policies to users..."
mc admin policy attach --insecure "$ALIAS" hr-readwrite --user=hr-manager
mc admin policy attach --insecure "$ALIAS" finance-readonly --user=finance-analyst
mc admin policy attach --insecure "$ALIAS" auditor-readonly --user=auditor
# guest-contractor intentionally gets NO policy attached -> default-deny, used in the
# unauthorized-access security test.

echo "[*] Current user roster:"
mc admin user list --insecure "$ALIAS"

echo "[+] MinIO environment initialized: buckets, versioning, SSE-S3 encryption, RBAC users."
