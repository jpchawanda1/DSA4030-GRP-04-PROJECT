#!/usr/bin/env bash
# TEST 02 — Role-based access control is enforced between departments.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/common.sh"
start_evidence "test02_rbac_enforcement"

log_section "OBJECTIVE"
echo "Confirm each authenticated user can only perform the S3 actions their attached IAM"
echo "policy allows: hr-manager (RW on hr-documents only), finance-analyst (RO on"
echo "finance-documents only), guest-contractor (authenticated, NO policy -> deny all)."

run_mc alias set hr-manager https://minio:9000 hr-manager "$HR_MANAGER_PASSWORD" --insecure >/dev/null
run_mc alias set finance-analyst https://minio:9000 finance-analyst "$FINANCE_ANALYST_PASSWORD" --insecure >/dev/null
run_mc alias set guest-contractor https://minio:9000 guest-contractor "$GUEST_PASSWORD" --insecure >/dev/null

log_section "POSITIVE CONTROL: hr-manager can list+read hr-documents (own bucket)"
run_mc ls hr-manager/hr-documents --insecure | head -5

log_section "NEGATIVE: hr-manager attempts to list finance-documents (foreign bucket)"
set +e
run_mc ls hr-manager/finance-documents --insecure
RC_HR_CROSS=$?
set -e
echo "--> exit code: $RC_HR_CROSS (non-zero / AccessDenied expected)"

log_section "POSITIVE CONTROL: finance-analyst can list+read finance-documents (own bucket, read-only)"
run_mc ls finance-analyst/finance-documents --insecure | head -5

log_section "NEGATIVE: finance-analyst attempts to WRITE to finance-documents (read-only policy)"
echo '{"test":"rbac-write-attempt"}' > "$EVIDENCE_DIR/rbac_write_test.json"
set +e
run_mc cp /evidence/rbac_write_test.json finance-analyst/finance-documents/rbac_write_test.json --insecure
RC_FIN_WRITE=$?
set -e
echo "--> exit code: $RC_FIN_WRITE (non-zero / AccessDenied expected, finance-analyst is read-only)"

log_section "NEGATIVE: guest-contractor (valid login, no policy) attempts to list any bucket"
set +e
run_mc ls guest-contractor/hr-documents --insecure
RC_GUEST=$?
set -e
echo "--> exit code: $RC_GUEST (non-zero / AccessDenied expected - authenticated but unauthorized)"

log_section "EXPECTED RESULT"
echo "Positive controls succeed; all three negative/cross-boundary attempts are denied."

log_section "ACTUAL RESULT"
if [ "$RC_HR_CROSS" -ne 0 ] && [ "$RC_FIN_WRITE" -ne 0 ] && [ "$RC_GUEST" -ne 0 ]; then
  echo "PASS - RBAC policies correctly enforced department/role boundaries."
else
  echo "FAIL - at least one RBAC boundary was not enforced."
fi
