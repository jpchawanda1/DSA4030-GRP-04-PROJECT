#!/usr/bin/env bash
# TEST 03 — Data in transit is encrypted (TLS-only) using the OpenSSL-issued certificate.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/common.sh"
start_evidence "test03_tls_enforcement"

PORT="${MINIO_API_PORT:-9000}"

log_section "OBJECTIVE"
echo "Confirm MinIO only serves the S3 API over TLS using our OpenSSL-issued certificate,"
echo "and that a plaintext (non-TLS) request on the same port is rejected."

log_section "PROCEDURE 1: TLS handshake + certificate chain verification against our CA"
openssl s_client -connect "localhost:${PORT}" -CAfile "$ROOT_DIR/certs/ca.crt" \
  -servername minio </dev/null > /tmp/tls_handshake.txt 2>&1 || true
grep -E "Verify return code|subject=|issuer=|Protocol|Cipher" /tmp/tls_handshake.txt || true
VERIFY_OK=$(grep -c "Verify return code: 0 (ok)" /tmp/tls_handshake.txt || true)
echo "--> Verify return code 0 (ok) occurrences: $VERIFY_OK"

log_section "PROCEDURE 2: Confirm certificate Subject/SAN matches our OpenSSL CN"
echo | openssl s_client -connect "localhost:${PORT}" -CAfile "$ROOT_DIR/certs/ca.crt" 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates

log_section "PROCEDURE 3: Attempt a PLAINTEXT HTTP request against the API port (should not succeed)"
set +e
HTTP_CODE=$(curl -s -m 5 -o /tmp/plaintext_response.txt -w "%{http_code}" "http://localhost:${PORT}/minio/health/live")
CURL_RC=$?
set -e
echo "--> curl exit code: $CURL_RC, http_code=$HTTP_CODE"
echo "--> response body:"
cat /tmp/plaintext_response.txt 2>/dev/null
echo
echo "(A raw-HTTP request against a TLS-only listener either resets the connection (curl exit"
echo " != 0) or, since it can't be parsed as a valid TLS ClientHello, MinIO's HTTP layer returns"
echo " an error status rather than the live/200 health response. Either way is TLS enforcement.)"

log_section "EXPECTED RESULT"
echo "1) TLS handshake succeeds and chains to our root CA (certs/ca.crt)."
echo "2) Certificate subject/SAN identifies the MinIO server we issued (CN=minio)."
echo "3) Plaintext HTTP request does NOT get a valid 200 /minio/health/live response."

log_section "ACTUAL RESULT"
if [ "$VERIFY_OK" -ge 1 ] && { [ "$CURL_RC" -ne 0 ] || [ "$HTTP_CODE" != "200" ]; }; then
  echo "PASS - MinIO enforces TLS-only access using our OpenSSL certificate."
else
  echo "FAIL - review handshake output above."
fi
