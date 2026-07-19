#!/usr/bin/env bash
# TEST 05 — Integrity verification: SHA-256 manifest catches corrupted/tampered objects.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/common.sh"
start_evidence "test05_integrity_verification"

SAMPLE_KEY="finance-documents/finance_shard_0001.jsonl"
MANIFEST="$ROOT_DIR/dataset/output/manifest.sha256.json"

log_section "OBJECTIVE"
echo "Confirm object integrity can be verified against the pre-upload SHA-256 manifest,"
echo "and that tampering with stored bytes is detected by a hash mismatch."

EXPECTED_SHA=$(python3 -c "import json; print(json.load(open('$MANIFEST'))['$SAMPLE_KEY']['sha256'])")
echo "Expected SHA-256 (from manifest, computed pre-upload): $EXPECTED_SHA"

log_section "PROCEDURE 1: BASELINE - download current object and verify hash matches manifest"
run_mc cat "grp4/${SAMPLE_KEY}" --insecure > "$EVIDENCE_DIR/baseline_download.jsonl"
BASELINE_SHA=$(shasum -a 256 "$EVIDENCE_DIR/baseline_download.jsonl" | awk '{print $1}')
echo "Downloaded object SHA-256: $BASELINE_SHA"
if [ "$BASELINE_SHA" = "$EXPECTED_SHA" ]; then
  echo "--> MATCH: object integrity intact."
else
  echo "--> MISMATCH (unexpected at baseline)."
fi

log_section "PROCEDURE 2: TAMPER - corrupt the object's bytes directly on the MinIO backend volume"
docker exec grp4-minio sh -c "
  for p in /data/finance-documents/finance_shard_0001.jsonl/*/part.1; do
    printf 'TAMPERED-BY-SECURITY-TEST' | dd of=\"\$p\" bs=1 seek=10 conv=notrunc 2>/dev/null
    echo \"corrupted: \$p\"
  done
"

log_section "PROCEDURE 3: Re-download the object and re-verify against the manifest"
set +e
run_mc cat "grp4/${SAMPLE_KEY}" --insecure > "$EVIDENCE_DIR/post_tamper_download.jsonl" 2> "$EVIDENCE_DIR/post_tamper_error.txt"
CAT_RC=$?
set -e
TAMPER_DETECTED=0
if [ "$CAT_RC" -ne 0 ]; then
  echo "--> mc cat FAILED after tampering (MinIO detected corrupted/checksum-invalid data):"
  cat "$EVIDENCE_DIR/post_tamper_error.txt"
  TAMPER_DETECTED=1
else
  POST_SHA=$(shasum -a 256 "$EVIDENCE_DIR/post_tamper_download.jsonl" | awk '{print $1}')
  echo "Post-tamper downloaded object SHA-256: $POST_SHA"
  if [ "$POST_SHA" != "$EXPECTED_SHA" ]; then
    echo "--> MISMATCH detected vs. manifest: tampering successfully identified by hash comparison."
    TAMPER_DETECTED=1
  else
    echo "--> MATCH (unexpected - tampering not detected)."
  fi
fi

log_section "PROCEDURE 4: Restore the object (re-upload known-good plaintext shard) so the environment stays consistent for later tests/demo"
run_mc cp "/dataset/finance-documents/finance_shard_0001.jsonl" "grp4/${SAMPLE_KEY}" --insecure
RESTORED_SHA=$(run_mc cat "grp4/${SAMPLE_KEY}" --insecure | shasum -a 256 | awk '{print $1}')
echo "Restored object SHA-256: $RESTORED_SHA"
[ "$RESTORED_SHA" = "$EXPECTED_SHA" ] && echo "--> Restore verified: hash matches manifest again." \
  || echo "--> WARNING: restore hash does not match manifest, investigate."

log_section "EXPECTED RESULT"
echo "Baseline hash matches manifest. After direct backend tampering, either (a) MinIO's"
echo "internal bitrot/checksum protection rejects the read, or (b) the re-downloaded"
echo "object's SHA-256 no longer matches the manifest - both prove tampering is detectable."
echo "The object is then restored from the original source shard (full end-to-end recovery"
echo "of a single-object corruption is also demonstrated bucket-wide in test_08)."

log_section "ACTUAL RESULT"
if [ "$BASELINE_SHA" = "$EXPECTED_SHA" ] && [ "$TAMPER_DETECTED" -eq 1 ] && [ "$RESTORED_SHA" = "$EXPECTED_SHA" ]; then
  echo "PASS - baseline verified, tampering detected, object successfully restored."
else
  echo "FAIL - review PROCEDURE 1/3/4 output above."
fi
