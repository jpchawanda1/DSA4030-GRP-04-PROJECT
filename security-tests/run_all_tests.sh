#!/usr/bin/env bash
# Runs the full security testing matrix (Part D) in order and writes a summary report.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$DIR/.." && pwd)"
SUMMARY="$ROOT_DIR/evidence/test_summary_$(date -u +%Y%m%dT%H%M%SZ).md"

echo "# Security Testing Matrix - Run Summary" > "$SUMMARY"
echo "" >> "$SUMMARY"
echo "Run started (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$SUMMARY"
echo "" >> "$SUMMARY"
echo "| # | Test | Result |" >> "$SUMMARY"
echo "|---|------|--------|" >> "$SUMMARY"

FAIL_COUNT=0
for script in "$DIR"/test_*.sh; do
  name="$(basename "$script" .sh)"
  echo
  echo "##################################################################"
  echo "# Running $name"
  echo "##################################################################"
  if bash "$script"; then
    RESULT="see evidence log"
  else
    RESULT="SCRIPT ERROR (non-zero exit)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
  echo "| ${name} | ${RESULT} |" >> "$SUMMARY"
done

echo "" >> "$SUMMARY"
echo "Run finished (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$SUMMARY"
echo "Scripts with a non-zero exit: $FAIL_COUNT" >> "$SUMMARY"
echo "Detailed PASS/FAIL verdicts are inside each individual evidence/*.log file (grep for 'PASS -' / 'FAIL -')." >> "$SUMMARY"

echo
echo "Summary written to: $SUMMARY"
echo "Per-test evidence logs: $ROOT_DIR/evidence/"
