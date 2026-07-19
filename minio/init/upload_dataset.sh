#!/bin/sh
# Uploads generated dataset shards into their matching MinIO buckets.
# Run via: docker compose run --rm mc /minio/init/upload_dataset.sh
set -eu

ALIAS=grp4
ENDPOINT="https://minio:9000"

mc alias set "$ALIAS" "$ENDPOINT" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" --insecure >/dev/null

for bucket in hr-documents finance-documents contracts-documents; do
  if [ -d "/dataset/$bucket" ]; then
    echo "[*] Uploading /dataset/$bucket -> $ALIAS/$bucket ..."
    mc mirror --insecure --overwrite /dataset/"$bucket" "$ALIAS/$bucket"
  else
    echo "[!] /dataset/$bucket not found - run dataset/generate_dataset.py first" >&2
    exit 1
  fi
done

echo "[*] Object counts per bucket:"
for bucket in hr-documents finance-documents contracts-documents; do
  count=$(mc ls --insecure "$ALIAS/$bucket" | wc -l | tr -d ' ')
  echo "    $bucket: $count objects"
done

echo "[+] Upload complete."
