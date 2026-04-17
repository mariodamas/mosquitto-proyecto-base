#!/bin/sh
# 07_validate_sca_emba.sh
# -----------------------
# Smoke-test for EMBA: run a minimal firmware analysis on the compiled
# Mosquitto ELF binary. EMBA requires Docker on the host.
#
# This script exits 0 (SKIP) if EMBA is not installed — validate_all.sh
# counts a SKIP as PASS. Document EMBA_HOME to override the default path.
#
# Prerequisites:
#   - Docker daemon running (Docker Desktop on Windows/WSL2)
#   - EMBA installed at EMBA_HOME (default: /opt/emba)
#   - Compiled Mosquitto binary at build/src/mosquitto
#
# Variables:
#   EMBA_HOME  : path to EMBA installation directory (default: /opt/emba)
#
# Exit codes:
#   0  — EMBA ran and produced output, OR EMBA not installed (SKIP)
#   1  — EMBA installed but analysis failed or output directory is empty

set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LAB_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RESULTS_DIR="${LAB_DIR}/validate/results"
mkdir -p "${RESULTS_DIR}"

EMBA_HOME="${EMBA_HOME:-/opt/emba}"

echo "=== [EMBA] validation starting ==="

# SKIP gracefully if EMBA is not installed — it requires a manual setup step
# and a Docker daemon; not available in all CI environments.
if [ ! -f "${EMBA_HOME}/emba" ]; then
    echo "SKIP: EMBA not installed at ${EMBA_HOME}." \
         "Set EMBA_HOME env var to override." >&2
    echo "=== [EMBA] validation SKIPPED (exit 0) ==="
    exit 0
fi

# Docker is a hard requirement for EMBA's module containers.
if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: Docker not found. EMBA requires the Docker daemon." >&2
    echo "       On WSL2: ensure Docker Desktop is running." >&2
    exit 1
fi

# Compiled binary must exist.
TARGET_BIN="${REPO_ROOT}/build/src/mosquitto"
if [ ! -f "${TARGET_BIN}" ]; then
    echo "ERROR: compiled binary not found at ${TARGET_BIN}." >&2
    echo "       Run cmake + make first (see .lab/docker/build_artifact.sh)." >&2
    exit 1
fi

echo "EMBA installation: ${EMBA_HOME}"

echo "--- Running EMBA firmware analysis on ${TARGET_BIN} ---"
# -f : firmware path (single ELF binary in this case)
# -l : log/output directory
# -p : scan profile — default-scan-no-notify avoids notification plugins
#      that require external credentials (Slack, email)
# -s : skip Docker-in-Docker check; needed when running on a bare host
#      rather than inside a container
"${EMBA_HOME}/emba" \
    -f "${TARGET_BIN}" \
    -l "${RESULTS_DIR}/emba_output" \
    -p "${EMBA_HOME}/scan-profiles/default-scan-no-notify.emba" \
    -s

# Post-run: output directory must exist and contain files.
if [ ! -d "${RESULTS_DIR}/emba_output" ]; then
    echo "ERROR: EMBA output directory ${RESULTS_DIR}/emba_output not created" >&2
    echo "=== [EMBA] validation FAILED ===" >&2
    exit 1
fi

OUTPUT_FILE_COUNT="$(find "${RESULTS_DIR}/emba_output" -type f | wc -l)"
if [ "${OUTPUT_FILE_COUNT}" -eq 0 ]; then
    echo "ERROR: EMBA output directory is empty" >&2
    echo "=== [EMBA] validation FAILED ===" >&2
    exit 1
fi

echo "EMBA produced ${OUTPUT_FILE_COUNT} output file(s) in ${RESULTS_DIR}/emba_output"
echo "=== [EMBA] validation PASSED ==="
