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
BUILD_DIR="${BUILD_DIR:-${REPO_ROOT}/build_cov}"
COV_INT_DIR="${RESULTS_DIR}/cov-int"

# Use an existing build directory if present, otherwise create one.
if [ ! -d "${BUILD_DIR}" ]; then
    BUILD_DIR="${REPO_ROOT}/build"
fi

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

echo "--- Pre-step: configure compiler mappings for gcc/cc wrappers ---"
"${COV_HOME}/bin/cov-configure" --comptype gcc --compiler /usr/bin/cc >/dev/null 2>&1 || true
"${COV_HOME}/bin/cov-configure" --comptype g++ --compiler /usr/bin/c++ >/dev/null 2>&1 || true

echo "--- Pre-step: ensure CMake build dir exists (docs disabled) ---"
cmake -S "${REPO_ROOT}" -B "${BUILD_DIR}" -DWITH_DOCS=OFF >/dev/null

echo "--- Step 1/3: cov-build (intercept Mosquitto compilation) ---"
# --dir : the intermediate directory where Coverity stores captured TUs.
#         We put it inside RESULTS_DIR so it gets cleaned with validate/results/.
rm -rf "${COV_INT_DIR}" >/dev/null 2>&1 || true
if [ -e "${COV_INT_DIR}" ]; then
    COV_INT_DIR="${RESULTS_DIR}/cov-int-$(date +%Y%m%d%H%M%S)-$$"
fi
echo "Coverity intermediate directory: ${COV_INT_DIR}"
make -C "${BUILD_DIR}" clean >/dev/null 2>&1 || true
"${COV_HOME}/bin/cov-build" \
    --config "${COV_HOME}/config/coverity_config.xml" \
    --dir "${COV_INT_DIR}" \
    make -C "${BUILD_DIR}" -B -j"$(nproc)" mosquitto libmosquitto

echo "--- Step 2/3: cov-analyze (run static analysis) ---"
# --all          : enable all checkers (equivalent to benchmark-sast default)
# --security     : include security-focused checkers (TAINTED_DATA, etc.)
# --concurrency  : include concurrency checkers (LOCK, DEADLOCK, etc.)
"${COV_HOME}/bin/cov-analyze" \
    --dir "${COV_INT_DIR}" \
    --all \
    --security \
    --concurrency

echo "--- Step 3/3: cov-format-errors (export findings JSON) ---"
"${COV_HOME}/bin/cov-format-errors" \
    --dir "${COV_INT_DIR}" \
    --json-output-v10 "${RESULTS_DIR}/coverity_result.json"

if [ ! -s "${RESULTS_DIR}/coverity_result.json" ]; then
    echo "ERROR: ${RESULTS_DIR}/coverity_result.json missing or empty" >&2
    echo "=== [Coverity] validation FAILED ===" >&2
    exit 1
fi

echo "Coverity findings saved to ${RESULTS_DIR}/coverity_result.json"
echo "=== [Coverity] validation PASSED ==="
