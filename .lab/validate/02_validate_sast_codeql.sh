#!/bin/sh
# 02_validate_sast_codeql.sh
# --------------------------
# Smoke-test for CodeQL CLI: create a C++ database from the Mosquitto source,
# run the cpp-security-and-quality query suite, and verify a SARIF file is
# produced. Follows the benchmark-sast checkout→db→analyze→SARIF flow.
#
# Prerequisites:
#   - Mosquitto must be compiled: build/src/mosquitto must exist
#   - CODEQL_BIN env var can override the codeql binary path (default: codeql)
#
# Exit codes:
#   0  — SARIF produced and finding count parsed
#   1  — binary missing / build not found / SARIF not produced

set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LAB_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RESULTS_DIR="${LAB_DIR}/validate/results"
mkdir -p "${RESULTS_DIR}"

# Allow callers to point at a non-PATH CodeQL installation.
CODEQL_BIN="${CODEQL_BIN:-codeql}"

echo "=== [CodeQL] validation starting ==="

# Availability check.
if ! command -v "${CODEQL_BIN}" >/dev/null 2>&1; then
    echo "ERROR: codeql not found at '${CODEQL_BIN}'. Run setup first." >&2
    exit 1
fi

"${CODEQL_BIN}" --version

# Compiled binary must exist; CodeQL needs to intercept a real build.
if [ ! -f "${REPO_ROOT}/build/src/mosquitto" ]; then
    echo "ERROR: compiled binary not found at ${REPO_ROOT}/build/src/mosquitto." >&2
    echo "       Run cmake + make first (see .lab/docker/build_artifact.sh)." >&2
    exit 1
fi

echo "--- Step 1/3: creating CodeQL C++ database ---"
# --language=cpp   : Mosquitto is a C project; CodeQL treats C and C++ together
# --command        : the build command CodeQL will trace to capture compilation
# --source-root    : where the source lives (all paths in the SARIF are relative to this)
# --overwrite      : allow re-running the script without manual cleanup
"${CODEQL_BIN}" database create "${RESULTS_DIR}/codeql-db" \
    --language=cpp \
    --command="make -C ${REPO_ROOT}/build -j$(nproc)" \
    --source-root="${REPO_ROOT}" \
    --overwrite

echo "--- Step 2/3: running cpp-security-and-quality suite ---"
# cpp-security-and-quality.qls : the bundled query suite; covers CWEs relevant
#                                 to a C broker (buffer overflows, format strings…)
# --format=sarif-latest         : Jenkins/GitHub Advanced Security can ingest SARIF
# --threads=0                   : use all available cores
"${CODEQL_BIN}" database analyze "${RESULTS_DIR}/codeql-db" \
    cpp-security-and-quality.qls \
    --format=sarif-latest \
    --output="${RESULTS_DIR}/codeql_result.sarif" \
    --threads=0

echo "--- Step 3/3: verifying SARIF output ---"
if [ ! -s "${RESULTS_DIR}/codeql_result.sarif" ]; then
    echo "ERROR: ${RESULTS_DIR}/codeql_result.sarif missing or empty" >&2
    echo "=== [CodeQL] validation FAILED ===" >&2
    exit 1
fi

python3 -c "
import json, sys
d = json.load(open('${RESULTS_DIR}/codeql_result.sarif'))
n = sum(len(r.get('results', [])) for r in d.get('runs', []))
print(f'CodeQL findings: {n}')
sys.exit(0)
"

echo "=== [CodeQL] validation PASSED ==="
