#!/bin/sh
# 01_validate_secrets.sh
# ----------------------
# Smoke-test for Gitleaks: confirm the tool is installed, runs against the
# synthetic-secret directory, and finds at least one secret.
#
# Exit codes:
#   0  — Gitleaks ran and found at least one secret (expected PASS)
#   1  — tool missing, JSON not produced, or JSON is empty

set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LAB_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RESULTS_DIR="${LAB_DIR}/validate/results"
mkdir -p "${RESULTS_DIR}"

echo "=== [Gitleaks] validation starting ==="

# Availability check — we must have the binary before anything else.
if ! command -v gitleaks >/dev/null 2>&1; then
    echo "ERROR: gitleaks not found. Run setup first." >&2
    exit 1
fi

# Print version so the log proves which binary was used.
gitleaks version

# --source        : scan only the synthetic-secrets directory, not the whole repo
# --report-format : machine-readable output for post-run parsing
# --report-path   : where to write the JSON findings file
# --verbose       : print each secret found to stdout for human review
#
# Gitleaks exits:
#   0  — no secrets found (would be a FAIL for our purposes)
#   1  — secrets found    (PASS — confirms the tool works)
#   >1 — tool error       (FAIL)
set +e
gitleaks detect \
    --source "${LAB_DIR}/secrets/" \
    --report-format json \
    --report-path "${RESULTS_DIR}/gitleaks_result.json" \
    --verbose
GITLEAKS_EXIT=$?
set -e

if [ "${GITLEAKS_EXIT}" -gt 1 ]; then
    echo "ERROR: gitleaks exited with code ${GITLEAKS_EXIT} (tool error, not findings)" >&2
    echo "=== [Gitleaks] validation FAILED ===" >&2
    exit 1
fi

# Post-run check: JSON must exist and be non-empty.
if [ ! -s "${RESULTS_DIR}/gitleaks_result.json" ]; then
    echo "ERROR: ${RESULTS_DIR}/gitleaks_result.json missing or empty" >&2
    echo "=== [Gitleaks] validation FAILED ===" >&2
    exit 1
fi

echo "Gitleaks findings saved to ${RESULTS_DIR}/gitleaks_result.json"
echo "Gitleaks exit code: ${GITLEAKS_EXIT} (0=no findings, 1=findings found — we expect 1)"

# Exit code 0 or 1 from gitleaks both count as PASS (tool functioned correctly).
echo "=== [Gitleaks] validation PASSED ==="
