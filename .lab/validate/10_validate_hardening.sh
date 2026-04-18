#!/bin/sh
# 10_validate_hardening.sh
# ------------------------
# Smoke-test for binary hardening checks: run checksec, hardening-check, and
# readelf against the compiled Mosquitto ELF to report its security properties.
#
# This script is INFORMATIONAL at this stage: missing hardening flags produce
# WARNING lines but do NOT cause a non-zero exit. The binary hardening posture
# is expected to improve as CMakeLists.lab.txt is hardened in later lab phases.
#
# Prerequisites:
#   - Compiled Mosquitto binary at build/src/mosquitto
#   - checksec and hardening-check installed (part of lab tooling setup)
#   - readelf is part of binutils (almost always present on Linux)
#
# Exit codes:
#   0  — all tools ran and produced output (even if hardening is incomplete)
#   1  — compiled binary missing or a tool is not available

set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LAB_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RESULTS_DIR="${RESULTS_DIR:-${LAB_DIR}/validate/results}"
mkdir -p "${RESULTS_DIR}"

TARGET_BIN="${REPO_ROOT}/build/src/mosquitto"

echo "=== [Hardening] validation starting ==="

# Compiled binary must exist before any tool runs.
if [ ! -f "${TARGET_BIN}" ]; then
    echo "ERROR: compiled binary not found at ${TARGET_BIN}." >&2
    echo "       Run cmake + make first (see .lab/docker/build_artifact.sh)." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Tool availability checks
# ---------------------------------------------------------------------------
if ! command -v checksec >/dev/null 2>&1; then
    echo "ERROR: checksec not found. Run setup first." >&2
    exit 1
fi

if ! command -v hardening-check >/dev/null 2>&1; then
    echo "ERROR: hardening-check not found. Run setup first." >&2
    exit 1
fi

if ! command -v readelf >/dev/null 2>&1; then
    echo "ERROR: readelf not found. Install binutils." >&2
    exit 1
fi

checksec --version 2>/dev/null | head -1 || true

# ---------------------------------------------------------------------------
# checksec
# ---------------------------------------------------------------------------
echo ""
echo "=== checksec ==="
# --output=json : machine-readable output for post-run parsing
checksec --file="${TARGET_BIN}" --output=json | tee "${RESULTS_DIR}/checksec_result.json"
echo ""
# Human-readable table (no --output flag = default text mode)
checksec --file="${TARGET_BIN}"

# ---------------------------------------------------------------------------
# hardening-check
# ---------------------------------------------------------------------------
echo ""
echo "=== hardening-check ==="
# hardening-check is a Debian/Ubuntu tool that inspects ELF security properties.
# It exits 1 when any check fails — we capture its output regardless.
set +e
hardening-check "${TARGET_BIN}" | tee "${RESULTS_DIR}/hardening_check_result.txt"
HARDENING_EXIT=$?
set -e
# Non-zero exit from hardening-check means incomplete hardening, not a script error.
if [ "${HARDENING_EXIT}" -ne 0 ]; then
    echo "NOTE: hardening-check reported incomplete hardening (exit ${HARDENING_EXIT})."
    echo "      This is informational — see .lab/docs/lab-decisions.md for roadmap."
fi

# ---------------------------------------------------------------------------
# readelf — RELRO, PIE, NX
# ---------------------------------------------------------------------------
echo ""
echo "=== readelf (RELRO, PIE, NX) ==="
# Extract GNU_RELRO, BIND_NOW (full RELRO), and GNU_STACK (NX) from dynamic section.
readelf -d "${TARGET_BIN}" \
    | grep -E 'RELRO|BIND_NOW|GNU_STACK' \
    | tee "${RESULTS_DIR}/readelf_security.txt" || true

# ---------------------------------------------------------------------------
# Post-run: parse checksec JSON and warn on missing protections
# ---------------------------------------------------------------------------
echo ""
echo "--- Hardening summary ---"
python3 -c "
import json, sys

try:
    raw = open('${RESULTS_DIR}/checksec_result.json').read().strip()
    d = json.loads(raw)
except Exception as e:
    print(f'WARNING: could not parse checksec JSON: {e}')
    sys.exit(0)

# checksec wraps results under the binary path as the key.
# Walk any nesting to find the properties dict.
def find_props(obj):
    if isinstance(obj, dict):
        # A properties dict has at least 'nx' or 'pie' keys.
        if 'nx' in obj or 'pie' in obj or 'stack_canary' in obj:
            return obj
        for v in obj.values():
            result = find_props(v)
            if result:
                return result
    return None

props = find_props(d)
if props is None:
    print('WARNING: could not locate property dict in checksec JSON')
    sys.exit(0)

checks = [
    ('stack_canary', 'Stack canary'),
    ('nx',           'NX (non-executable stack)'),
    ('pie',          'PIE (position-independent executable)'),
]
all_ok = True
for key, label in checks:
    val = props.get(key, 'unknown')
    status = 'OK' if val in ('yes', '1', True) else 'WARNING'
    if status == 'WARNING':
        all_ok = False
    print(f'  {status}: {label} = {val}')

if not all_ok:
    print('Some hardening flags are missing — review CMakeLists.lab.txt.')
    print('This is a WARNING, not a failure (hardening is iterative).')
"

echo ""
echo "Results saved:"
echo "  ${RESULTS_DIR}/checksec_result.json"
echo "  ${RESULTS_DIR}/hardening_check_result.txt"
echo "  ${RESULTS_DIR}/readelf_security.txt"
echo "=== [Hardening] validation PASSED ==="
