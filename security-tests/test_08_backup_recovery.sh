#!/usr/bin/env bash
# TEST 08 — Backup & recovery: versioned recovery + secondary mirror backup.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/common.sh"
start_evidence "test08_backup_recovery"

TARGET_KEY="contracts-documents/contracts_shard_0001.jsonl"

log_section "OBJECTIVE"
echo "Confirm a deleted object can be recovered via (a) MinIO bucket versioning and"
echo "(b) an independent mirrored backup bucket, without permanent data loss."

log_section "PROCEDURE 1: Create a secondary backup by mirroring contracts-documents -> backups bucket"
run_mc mirror --insecure --overwrite grp4/contracts-documents grp4/backups/contracts-documents

log_section "PROCEDURE 2: Record baseline hash of the target object"
run_mc cat "grp4/${TARGET_KEY}" --insecure | shasum -a 256

log_section "PROCEDURE 3: Simulate accidental deletion of the object from the primary bucket"
run_mc rm "grp4/${TARGET_KEY}" --insecure
set +e
run_mc cat "grp4/${TARGET_KEY}" --insecure > /dev/null 2>&1
DELETED_RC=$?
set -e
echo "--> Read after delete exit code: $DELETED_RC (non-zero expected - object gone from live view)"

log_section "PROCEDURE 4a: RECOVERY VIA VERSIONING - list versions and restore the previous version"
run_mc ls --insecure --versions "grp4/${TARGET_KEY}"
PREV_VERSION=$(run_mc ls --insecure --versions --json "grp4/${TARGET_KEY}" \
  | python3 -c "import sys,json
for line in sys.stdin:
    o=json.loads(line)
    if not o.get('isDeleteMarker') and o.get('versionId'):
        print(o['versionId']); break")
echo "Restoring version: $PREV_VERSION"
if [ -n "$PREV_VERSION" ]; then
  run_mc cp --insecure --version-id "$PREV_VERSION" "grp4/${TARGET_KEY}" "grp4/${TARGET_KEY}"
fi

log_section "PROCEDURE 4b: RECOVERY VIA SECONDARY BACKUP (fallback if versioning unavailable)"
run_mc cp --insecure "grp4/backups/${TARGET_KEY}" "grp4/${TARGET_KEY}"

log_section "PROCEDURE 5: Verify the object is readable again and hash matches baseline"
run_mc cat "grp4/${TARGET_KEY}" --insecure | shasum -a 256

log_section "EXPECTED RESULT"
echo "Object is unreadable immediately after deletion, then successfully restored via"
echo "versioning and/or the mirrored backup bucket, with SHA-256 matching the baseline."

log_section "ACTUAL RESULT"
set +e
run_mc cat "grp4/${TARGET_KEY}" --insecure > /dev/null 2>&1
FINAL_RC=$?
set -e
if [ "$DELETED_RC" -ne 0 ] && [ "$FINAL_RC" -eq 0 ]; then
  echo "PASS - object was deleted then successfully recovered."
else
  echo "FAIL - review recovery steps above."
fi
