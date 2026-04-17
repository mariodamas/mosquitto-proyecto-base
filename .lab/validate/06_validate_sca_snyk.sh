#!/bin/sh
# 06_validate_sca_snyk.sh
# -----------------------
# Smoke-test for Snyk CLI in --unmanaged mode: scan the intentionally
# vulnerable vendored dependency (cJSON 1.7.14) for known CVEs.
# Follows the benchmark-sca phase2 Snyk --unmanaged pattern.
#
# Prerequisites:
#   SNYK_TOKEN environment variable must be set to a valid Snyk API token.
#   The vendored library must exist at .lab/vendor/cjson-1.7.14/.
#
# Note: Snyk exits non-zero when vulnerabilities are found. Exit codes:
#   0  — no vulnerabilities (tool ran correctly)
#   1  — vulnerabilities found (also PASS — tool ran correctly)
#   >1 — tool error (FAIL)
#
# Exit codes for this script:
#   0  — Snyk ran correctly (0 or 1 from Snyk)
#   1  — SNYK_TOKEN missing, vendor dir missing, or Snyk tool error

set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LAB_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RESULTS_DIR="${LAB_DIR}/validate/results"
mkdir -p "${RESULTS_DIR}"

echo "=== [Snyk] validation starting ==="

# Token check — Snyk CLI requires authentication; fail early with a clear message.
if [ -z "${SNYK_TOKEN:-}" ]; then
    echo "ERROR: SNYK_TOKEN environment variable not set." >&2
    echo "       Export a valid Snyk API token before running this script." >&2
    exit 1
fi

# Availability check.
if ! command -v snyk >/dev/null 2>&1; then
    echo "ERROR: snyk not found. Run setup first." >&2
    exit 1
fi

snyk --version

# Vendored dependency must exist (created as part of lab branch setup).
VENDOR_DIR="${LAB_DIR}/vendor/cjson-1.7.14"
if [ ! -d "${VENDOR_DIR}" ]; then
    echo "ERROR: ${VENDOR_DIR} not found." >&2
    echo "       The lab branch should include this vendored dependency." >&2
    exit 1
fi

echo "--- Running Snyk --unmanaged on ${VENDOR_DIR} ---"
# --unmanaged : fingerprint-based scan for C/C++ vendored code without a
#               package manifest; matches source hashes against Snyk's vuln DB.
# --json      : machine-readable output piped to the results file.
# 2>&1        : capture both stdout (JSON) and stderr (progress/auth messages).
#
# Snyk exits 0 (no vulns) or 1 (vulns found) — both are PASS for this smoke-test.
# Exit >1 means a tool/auth error — that is a FAIL.
set +e
snyk test --unmanaged "${VENDOR_DIR}" \
    --json > "${RESULTS_DIR}/snyk_unmanaged_result.json" 2>&1
SNYK_EXIT=$?
set -e

if [ "${SNYK_EXIT}" -gt 1 ]; then
    echo "ERROR: Snyk exited with code ${SNYK_EXIT} (tool error, not findings)" >&2
    echo "       Check ${RESULTS_DIR}/snyk_unmanaged_result.json for details." >&2
    echo "=== [Snyk] validation FAILED ===" >&2
    exit 1
fi

# Post-run: parse the JSON to surface the finding count.
if [ -s "${RESULTS_DIR}/snyk_unmanaged_result.json" ]; then
    python3 -c "
import json, sys
try:
    d = json.load(open('${RESULTS_DIR}/snyk_unmanaged_result.json'))
    # Snyk unmanaged JSON may have 'vulnerabilities' or 'issues' key depending on version.
    vulns = d.get('vulnerabilities', d.get('issues', []))
    print(f'Snyk vulnerabilities found: {len(vulns)}')
except Exception as e:
    print(f'Note: could not parse JSON ({e}) — raw output in results file')
" || true
fi

echo "Snyk exit code: ${SNYK_EXIT} (0=no vulns, 1=vulns found — both are PASS)"
echo "Snyk findings saved to ${RESULTS_DIR}/snyk_unmanaged_result.json"
echo "=== [Snyk] validation PASSED ==="
