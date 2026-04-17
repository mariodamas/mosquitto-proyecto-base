#!/bin/sh
# 05_validate_sca_grype.sh
# ------------------------
# Smoke-test for Grype: scan the CycloneDX SBOM produced by
# 04_validate_sbom_syft.sh and report vulnerability matches.
# Follows the benchmark-sca phase1 Grype pattern.
#
# Prerequisites:
#   Run 04_validate_sbom_syft.sh first to produce sbom-cyclonedx.json.
#
# Note: Grype may find 0 vulnerabilities if Mosquitto's source SBOM has no
# declared vulnerable components. This is a PASS — the tool ran correctly.
#
# Exit codes:
#   0  — Grype ran and produced parseable JSON output
#   1  — tool missing, SBOM not found, or JSON output malformed

set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LAB_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RESULTS_DIR="${LAB_DIR}/validate/results"
mkdir -p "${RESULTS_DIR}"

echo "=== [Grype] validation starting ==="

# Availability check.
if ! command -v grype >/dev/null 2>&1; then
    echo "ERROR: grype not found. Run setup first." >&2
    exit 1
fi

grype version

# Grype needs the SBOM that Syft produced; enforce the dependency explicitly.
if [ ! -f "${RESULTS_DIR}/sbom-cyclonedx.json" ]; then
    echo "ERROR: ${RESULTS_DIR}/sbom-cyclonedx.json not found." >&2
    echo "       Run 04_validate_sbom_syft.sh first." >&2
    exit 1
fi

echo "--- Scanning SBOM with Grype (JSON output) ---"
# sbom: prefix tells Grype to read an existing SBOM rather than scan an image.
# --output json  : machine-readable output for post-run parsing and Jenkins.
grype sbom:"${RESULTS_DIR}/sbom-cyclonedx.json" \
    --output json > "${RESULTS_DIR}/grype_result.json"

echo "--- Grype human-readable table ---"
# Second pass with --output table for console readability; no file capture needed.
grype sbom:"${RESULTS_DIR}/sbom-cyclonedx.json" \
    --output table

echo "--- Verifying Grype output ---"
if [ ! -s "${RESULTS_DIR}/grype_result.json" ]; then
    echo "ERROR: ${RESULTS_DIR}/grype_result.json missing or empty" >&2
    echo "=== [Grype] validation FAILED ===" >&2
    exit 1
fi

python3 -c "
import json
d = json.load(open('${RESULTS_DIR}/grype_result.json'))
n = len(d.get('matches', []))
print(f'Grype vulnerabilities found: {n}')
# 0 is a valid result (no known vulnerable deps in the SBOM)
"

echo "Grype findings saved to ${RESULTS_DIR}/grype_result.json"
echo "=== [Grype] validation PASSED ==="
