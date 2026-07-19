#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker is required to start the environment."
  exit 1
fi

if docker compose version >/dev/null 2>&1; then
  COMPOSE="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE="docker-compose"
else
  echo "ERROR: docker compose is required to start the environment."
  exit 1
fi

MINIO_API_PORT=${MINIO_API_PORT:-9000}
MINIO_CONSOLE_PORT=${MINIO_CONSOLE_PORT:-9001}
WEBHOOK_PORT=${AUDIT_WEBHOOK_PORT:-8080}

echo "Starting Docker services: minio, clamav, audit-webhook"
$COMPOSE up -d --build minio clamav audit-webhook

echo "Waiting for MinIO to become healthy on https://localhost:${MINIO_API_PORT}..."
for i in $(seq 1 30); do
  if command -v curl >/dev/null 2>&1 && curl -kfsS "https://localhost:${MINIO_API_PORT}/minio/health/live" >/dev/null 2>&1; then
    echo "MinIO is healthy."
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "ERROR: MinIO did not become healthy within 60 seconds."
    exit 1
  fi
  sleep 2
done

echo
echo "Open these in your browser:"
echo "  MinIO Console: https://localhost:${MINIO_CONSOLE_PORT}"
echo "  MinIO API:     https://localhost:${MINIO_API_PORT}"
echo "  Audit events:  http://localhost:${WEBHOOK_PORT}/events"
echo "  Webhook root:  http://localhost:${WEBHOOK_PORT}/"
echo "  Health check:  http://localhost:${WEBHOOK_PORT}/healthz"

echo
echo "Docker services are running. The audit-webhook service is already exposed on port ${WEBHOOK_PORT}."