#!/usr/bin/env bash
# TEST 01 — Unauthorized (unauthenticated / bad-credential) access is rejected.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/common.sh"
start_evidence "test01_unauthorized_access"

log_section "OBJECTIVE"
echo "Confirm MinIO rejects requests presenting no credentials, or invalid credentials,"
echo "when attempting to list/read a private bucket (hr-documents)."

log_section "PROCEDURE 1: mc client with a bogus access key / secret key"
set +e
run_mc alias set badactor https://minio:9000 wrong-access-key wrong-secret-key --insecure
run_mc ls badactor/hr-documents --insecure
RC1=$?
set -e
echo "--> mc exit code: $RC1 (non-zero expected)"

log_section "PROCEDURE 2: Anonymous curl GET against a known object, no auth header"
set +e
HTTP_CODE=$(curl -sk -o /tmp/anon_response.xml -w "%{http_code}" \
  "https://localhost:${MINIO_API_PORT:-9000}/hr-documents/hr_shard_0001.jsonl")
set -e
echo "--> HTTP status code: $HTTP_CODE (403 or 400 expected, not 200)"
echo "--> Response body:"
cat /tmp/anon_response.xml
echo

log_section "EXPECTED RESULT"
echo "1) mc command fails with an authentication/AccessDenied error (non-zero exit)."
echo "2) Anonymous HTTP GET returns 403 Forbidden (bucket has no public/anonymous policy)."

log_section "ACTUAL RESULT"
if [ "$RC1" -ne 0 ] && [ "$HTTP_CODE" != "200" ]; then
  echo "PASS - both unauthorized attempts were rejected."
else
  echo "FAIL - an unauthorized request unexpectedly succeeded."
fi
