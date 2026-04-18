#!/bin/sh
# 07_validate_sca_emba.sh
# -----------------------
# Smoke-test for EMBA: run a minimal firmware analysis on the compiled
# Mosquitto ELF binary. EMBA requires Docker on the host.
#
# This script exits 0 (SKIP) if EMBA or Docker are not available.
# validate_all.sh counts a SKIP as PASS.
#
# Prerequisites:
#   - Docker daemon running (Docker Desktop on Windows/WSL2)
#   - EMBA installed in one of the supported paths
#   - Compiled Mosquitto binary at build/src/mosquitto
#
# Variables:
#   EMBA_HOME            : preferred EMBA root (default: /opt/emba)
#   EMBA_TIMEOUT_SECONDS : timeout for EMBA run, 0 disables timeout (default: 600)
#   EMBA_FORCE_MODE      : pass -F to EMBA when set to 1 (default: 0)
#
# Exit codes:
#   0  — EMBA ran and produced output, OR prerequisites unavailable (SKIP)
#   1  — EMBA installed but analysis failed or output directory is empty

set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LAB_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RESULTS_DIR="${RESULTS_DIR:-${LAB_DIR}/validate/results}"
mkdir -p "${RESULTS_DIR}"

EMBA_HOME="${EMBA_HOME:-/opt/emba}"
EMBA_TIMEOUT_SECONDS="${EMBA_TIMEOUT_SECONDS:-600}"
EMBA_FORCE_MODE="${EMBA_FORCE_MODE:-0}"

TARGET_BIN="${REPO_ROOT}/build/src/mosquitto"
STATUS_FILE="${RESULTS_DIR}/emba_status.json"
LOG_FILE="${RESULTS_DIR}/emba_run.log"
OUTPUT_DIR="${RESULTS_DIR}/emba_output"
RUN_BASE="/tmp/emba_validate_$$"
RUN_INPUT_DIR="${RUN_BASE}/input"
RUN_OUTPUT_DIR="${RUN_BASE}/output"
RUN_TARGET_BIN="${RUN_INPUT_DIR}/mosquitto"

status="blocked"
reason=""
install_hint=""
emba_cmd=""
emba_root=""
report_path=""
run_exit=""
output_file_count="0"

cleanup_tmp()
{
    rm -rf "${RUN_BASE}" 2>/dev/null || true
}

trap cleanup_tmp EXIT

write_status()
{
    STATUS_FILE="${STATUS_FILE}" \
    STATUS="${status}" \
    REASON="${reason}" \
    TARGET_BIN="${TARGET_BIN}" \
    EMBA_CMD="${emba_cmd}" \
    EMBA_ROOT="${emba_root}" \
    INSTALL_HINT="${install_hint}" \
    REPORT_PATH="${report_path}" \
    LOG_FILE="${LOG_FILE}" \
    EMBA_TIMEOUT_SECONDS="${EMBA_TIMEOUT_SECONDS}" \
    EMBA_FORCE_MODE="${EMBA_FORCE_MODE}" \
    RUN_EXIT="${run_exit}" \
    OUTPUT_FILE_COUNT="${output_file_count}" \
    python3 - <<'PY'
import json
import os


def as_int(name, default=0):
    try:
        return int(os.environ.get(name, str(default)))
    except Exception:
        return default


payload = {
    "tool": "EMBA",
    "status": os.environ.get("STATUS", ""),
    "reason": os.environ.get("REASON", ""),
    "binary": os.environ.get("TARGET_BIN", ""),
    "emba_cmd": os.environ.get("EMBA_CMD", ""),
    "emba_root": os.environ.get("EMBA_ROOT", ""),
    "install_hint": os.environ.get("INSTALL_HINT", ""),
    "report_path": os.environ.get("REPORT_PATH", ""),
    "log_file": os.environ.get("LOG_FILE", ""),
    "timeout_seconds": as_int("EMBA_TIMEOUT_SECONDS", 600),
    "force_mode": as_int("EMBA_FORCE_MODE", 0),
    "run_exit": os.environ.get("RUN_EXIT", ""),
    "output_file_count": as_int("OUTPUT_FILE_COUNT", 0),
}

with open(os.environ["STATUS_FILE"], "w", encoding="utf-8") as f:
    json.dump(payload, f, indent=2)

print("EMBA status saved to {}".format(os.environ["STATUS_FILE"]))
PY
}

finish()
{
    code="$1"
    write_status
    exit "${code}"
}

echo "=== [EMBA] validation starting ==="

case "${EMBA_TIMEOUT_SECONDS}" in
    ''|*[!0-9]*)
        status="error"
        reason="invalid_timeout"
        echo "ERROR: invalid EMBA_TIMEOUT_SECONDS=${EMBA_TIMEOUT_SECONDS}" >&2
        echo "=== [EMBA] validation FAILED ===" >&2
        finish 1
        ;;
esac

case "${EMBA_FORCE_MODE}" in
    0|1)
        ;;
    *)
        status="error"
        reason="invalid_force_mode"
        echo "ERROR: EMBA_FORCE_MODE must be 0 or 1" >&2
        echo "=== [EMBA] validation FAILED ===" >&2
        finish 1
        ;;
esac

if [ ! -f "${TARGET_BIN}" ]; then
    status="error"
    reason="binary_not_found"
    echo "ERROR: compiled binary not found at ${TARGET_BIN}." >&2
    echo "       Run cmake + make first (see .lab/docker/build_artifact.sh)." >&2
    echo "=== [EMBA] validation FAILED ===" >&2
    finish 1
fi

# Discover EMBA in common WSL locations.
if [ -x "${EMBA_HOME}/emba" ]; then
    emba_cmd="${EMBA_HOME}/emba"
    emba_root="${EMBA_HOME}"
elif [ -x "${HOME}/tools/emba/emba" ]; then
    emba_cmd="${HOME}/tools/emba/emba"
    emba_root="${HOME}/tools/emba"
elif command -v emba >/dev/null 2>&1; then
    emba_cmd="$(command -v emba)"
    emba_root="$(dirname "${emba_cmd}")"
elif [ -x "${REPO_ROOT}/emba/emba" ]; then
    emba_cmd="${REPO_ROOT}/emba/emba"
    emba_root="${REPO_ROOT}/emba"
elif [ -x "${HOME}/emba/emba" ]; then
    emba_cmd="${HOME}/emba/emba"
    emba_root="${HOME}/emba"
fi

if [ -z "${emba_cmd}" ]; then
    status="blocked"
    reason="emba_missing"
    install_hint="set_EMBA_HOME_or_install_emba"
    echo "SKIP: EMBA executable not found." >&2
    echo "      Checked: ${EMBA_HOME}/emba, ${HOME}/tools/emba/emba, PATH, ${REPO_ROOT}/emba/emba, ${HOME}/emba/emba" >&2
    echo "=== [EMBA] validation SKIPPED (exit 0) ==="
    finish 0
fi

# Docker is a hard requirement for EMBA's module containers.
if ! command -v docker >/dev/null 2>&1; then
    status="blocked"
    reason="docker_missing"
    install_hint="install_docker_desktop_and_enable_wsl_integration"
    echo "SKIP: Docker not found. EMBA requires Docker." >&2
    echo "=== [EMBA] validation SKIPPED (exit 0) ==="
    finish 0
fi

if ! docker info >/dev/null 2>&1; then
    status="blocked"
    reason="docker_unavailable"
    install_hint="start_docker_daemon_or_enable_wsl_integration"
    echo "SKIP: Docker daemon not reachable from WSL." >&2
    echo "=== [EMBA] validation SKIPPED (exit 0) ==="
    finish 0
fi

echo "EMBA executable: ${emba_cmd}"
echo "EMBA root: ${emba_root}"

echo "--- Running EMBA firmware analysis on ${TARGET_BIN} ---"

rm -rf "${RUN_BASE}"
mkdir -p "${RUN_INPUT_DIR}" "${RUN_OUTPUT_DIR}"
cp "${TARGET_BIN}" "${RUN_TARGET_BIN}"
chmod +x "${RUN_TARGET_BIN}" || true

report_path="${OUTPUT_DIR}"

EMBA_PROFILE="${emba_root}/scan-profiles/default-scan-no-notify.emba"

set -- -f "${RUN_TARGET_BIN}" -l "${RUN_OUTPUT_DIR}" -s -y
if [ "${EMBA_FORCE_MODE}" = "1" ]; then
    set -- "$@" -F
fi
if [ -f "${EMBA_PROFILE}" ]; then
    set -- "$@" -p "${EMBA_PROFILE}"
fi

set +e
if [ "${EMBA_TIMEOUT_SECONDS}" -gt 0 ] && command -v timeout >/dev/null 2>&1; then
    (
        cd "${emba_root}" || exit 1
        # EMBA can ask interactive confirmation when it detects host log files.
        # Feed affirmative answers to keep validate stages non-interactive.
        yes Y | timeout --signal=TERM --kill-after=30s "${EMBA_TIMEOUT_SECONDS}s" "${emba_cmd}" "$@"
    ) > "${LOG_FILE}" 2>&1
    run_exit=$?
else
    (
        cd "${emba_root}" || exit 1
        yes Y | "${emba_cmd}" "$@"
    ) > "${LOG_FILE}" 2>&1
    run_exit=$?
fi
set -e

if [ "${run_exit}" -eq 124 ]; then
    status="timeout"
    reason="emba_timeout_${EMBA_TIMEOUT_SECONDS}s"
    echo "ERROR: EMBA execution timed out after ${EMBA_TIMEOUT_SECONDS}s" >&2
    echo "=== [EMBA] validation FAILED ===" >&2
    finish 1
fi

if [ "${run_exit}" -ne 0 ]; then
    status="error"
    reason="emba_exit_${run_exit}"
    echo "ERROR: EMBA exited with code ${run_exit}" >&2
    echo "       See ${LOG_FILE}" >&2
    echo "=== [EMBA] validation FAILED ===" >&2
    finish 1
fi

# Sync EMBA output from temporary no-space path back to lab results path.
rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"
cp -a "${RUN_OUTPUT_DIR}/." "${OUTPUT_DIR}/"

# Post-run: output directory must exist and contain files.
if [ ! -d "${OUTPUT_DIR}" ]; then
    status="error"
    reason="output_dir_missing"
    echo "ERROR: EMBA output directory ${OUTPUT_DIR} not created" >&2
    echo "=== [EMBA] validation FAILED ===" >&2
    finish 1
fi

output_file_count="$(find "${OUTPUT_DIR}" -type f | wc -l | tr -d '[:space:]')"
if [ -z "${output_file_count}" ]; then
    output_file_count="0"
fi

if [ "${output_file_count}" -eq 0 ]; then
    status="error"
    reason="output_empty"
    echo "ERROR: EMBA output directory is empty" >&2
    echo "=== [EMBA] validation FAILED ===" >&2
    finish 1
fi

status="ok"
reason="executed"

echo "EMBA produced ${output_file_count} output file(s) in ${OUTPUT_DIR}"
echo "=== [EMBA] validation PASSED ==="
finish 0
