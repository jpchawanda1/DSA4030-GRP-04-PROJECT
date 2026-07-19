#!/usr/bin/env bash
# One-shot bootstrap for the whole environment:
#   certs -> .env -> docker compose up -> MinIO init (buckets/RBAC/encryption)
#   -> dataset generation -> manifest -> upload -> ready for security-tests/.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

RECORDS_PER_CATEGORY="${1:-40000}"

echo "[1/8] Checking prerequisites..."
command -v docker >/dev/null || { echo "docker is required"; exit 1; }
command -v python3 >/dev/null || { echo "python3 is required"; exit 1; }

if [ ! -f .env ]; then
  echo "[*] .env not found, copying from .env.example"
  cp .env.example .env
fi

if [ ! -f certs/public.crt ] || [ ! -f certs/private.key ]; then
  echo "[2/8] Generating OpenSSL TLS certificates..."
  bash scripts/gen_certs.sh
else
  echo "[2/8] TLS certificates already present, skipping."
fi

echo "[3/8] Building and starting docker compose services (minio, audit-webhook, clamav)..."
docker compose up -d --build minio audit-webhook clamav

echo "[4/8] Waiting for MinIO to report healthy..."
for i in $(seq 1 30); do
  status=$(docker inspect --format='{{.State.Health.Status}}' grp4-minio 2>/dev/null || echo "unknown")
  if [ "$status" = "healthy" ]; then
    echo "    MinIO is healthy."
    break
  fi
  sleep 2
done

echo "[5/8] Initializing MinIO (buckets, versioning, SSE-S3 encryption, RBAC users/policies)..."
docker compose run --rm --entrypoint /bin/sh mc /minio/init/init-minio.sh

echo "[6/8] Generating synthetic dataset (${RECORDS_PER_CATEGORY} records x 3 categories)..."
if [ ! -d dataset/.venv ]; then
  python3 -m venv dataset/.venv
fi
# shellcheck disable=SC1091
source dataset/.venv/bin/activate
pip install -q -r dataset/requirements.txt
python3 dataset/generate_dataset.py --records-per-category "$RECORDS_PER_CATEGORY"
python3 dataset/build_manifest.py
deactivate

echo "[7/8] Uploading dataset shards into MinIO buckets..."
docker compose run --rm --entrypoint /bin/sh mc /minio/init/upload_dataset.sh

echo "[8/8] Done."
echo
echo "MinIO Console:  https://localhost:${MINIO_CONSOLE_PORT:-9001}  (self-signed cert, add exception)"
echo "MinIO API:      https://localhost:${MINIO_API_PORT:-9000}"
echo "Audit log API:  http://localhost:${AUDIT_WEBHOOK_PORT:-8080}/events"
echo
echo "Next: run the security testing matrix with: bash security-tests/run_all_tests.sh"
