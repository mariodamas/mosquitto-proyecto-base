#!/bin/sh
# 03_validate_sast_coverity.sh
# ----------------------------
# Smoke-test for Coverity: run cov-build to intercept the Mosquitto build,
# then cov-analyze to produce a JSON v8 findings report. Follows the
# benchmark-sast Coverity runner pattern.
#
# Coverity requires a corporate license and is not available in all
# environments. This script exits 0 (SKIP) if Coverity is not installed —
# validate_all.sh counts a SKIP as PASS so the pipeline does not fail.
#
# Variables:
#   COV_HOME  : path to Coverity installation (default: /opt/cov-analysis)
#
# Exit codes:
#   0  — Coverity ran and produced a JSON report, OR Coverity not installed (SKIP)
#   1  — Coverity installed but analysis failed

set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LAB_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RESULTS_DIR="${RESULTS_DIR:-${LAB_DIR}/validate/results}"
mkdir -p "${RESULTS_DIR}"

# Allow callers to override the Coverity installation path.
COV_HOME="${COV_HOME:-/opt/cov-analysis}"

echo "=== [Coverity] validation starting ==="

# SKIP gracefully if Coverity is not installed — this is expected in most
# open-source CI environments; a corporate license is required.
if [ ! -d "${COV_HOME}" ]; then
    echo "SKIP: Coverity not installed at ${COV_HOME}." \
         "Set COV_HOME env var to override." >&2
    echo "=== [Coverity] validation SKIPPED (exit 0) ==="
    exit 0
fi

echo "Coverity installation: ${COV_HOME}"
"${COV_HOME}/bin/cov-build" --version 2>/dev/null | head -1 || true

echo "--- Step 1/2: cov-build (intercept Mosquitto compilation) ---"
# --dir : the intermediate directory where Coverity stores captured TUs.
#         We put it inside RESULTS_DIR so it gets cleaned with validate/results/.
"${COV_HOME}/bin/cov-build" \
    --dir "${RESULTS_DIR}/cov-int" \
    make -C "${REPO_ROOT}/build" -j"$(nproc)"

echo "--- Step 2/2: cov-analyze (produce findings) ---"
# --all          : enable all checkers (equivalent to benchmark-sast default)
# --security     : include security-focused checkers (TAINTED_DATA, etc.)
# --concurrency  : include concurrency checkers (LOCK, DEADLOCK, etc.)
# --output-format json : JSON v8 format for downstream parsing
# --output-file  : where to write the findings
"${COV_HOME}/bin/cov-analyze" \
    --dir "${RESULTS_DIR}/cov-int" \
    --all \
    --security \
    --concurrency \
    --output-format json \
    --output-file "${RESULTS_DIR}/coverity_result.json"

if [ ! -s "${RESULTS_DIR}/coverity_result.json" ]; then
    echo "ERROR: ${RESULTS_DIR}/coverity_result.json missing or empty" >&2
    echo "=== [Coverity] validation FAILED ===" >&2
    exit 1
fi

echo "Coverity findings saved to ${RESULTS_DIR}/coverity_result.json"
echo "=== [Coverity] validation PASSED ==="
