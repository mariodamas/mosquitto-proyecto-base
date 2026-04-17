#!/bin/sh
# 04_validate_sbom_syft.sh
# ------------------------
# Smoke-test for Syft: generate a CycloneDX JSON and SPDX JSON SBOM from the
# Mosquitto source tree. Follows the benchmark-sca phase1 Syft pattern.
#
# Output:
#   ${RESULTS_DIR}/sbom-cyclonedx.json  — consumed by 05_validate_sca_grype.sh
#   ${RESULTS_DIR}/sbom-spdx.json
#
# Exit codes:
#   0  — both SBOM files produced and contain at least one component
#   1  — tool missing, files not produced, or zero components found

set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LAB_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RESULTS_DIR="${LAB_DIR}/validate/results"
mkdir -p "${RESULTS_DIR}"

echo "=== [Syft] validation starting ==="

# Availability check.
if ! command -v syft >/dev/null 2>&1; then
    echo "ERROR: syft not found. Run setup first." >&2
    exit 1
fi

syft version

# Use lab-specific Syft config if it exists (placed under .lab/sca/); otherwise
# Syft runs with its built-in defaults which is sufficient for a smoke-test.
SYFT_CONFIG_ARGS=""
if [ -f "${LAB_DIR}/sca/.syft.yaml" ]; then
    # --config : path to .syft.yaml; controls catalogers, output options, etc.
    SYFT_CONFIG_ARGS="--config ${LAB_DIR}/sca/.syft.yaml"
    echo "Using Syft config: ${LAB_DIR}/sca/.syft.yaml"
fi

echo "--- Generating SBOM from Mosquitto source tree ---"
# dir: prefix tells Syft to scan a directory (source-mode), not an image.
# Two --output flags produce both formats in a single pass to avoid double-scanning.
# shellcheck disable=SC2086
syft dir:"${REPO_ROOT}" \
    ${SYFT_CONFIG_ARGS} \
    --output cyclonedx-json="${RESULTS_DIR}/sbom-cyclonedx.json" \
    --output spdx-json="${RESULTS_DIR}/sbom-spdx.json"

echo "--- Verifying SBOM output ---"

if [ ! -s "${RESULTS_DIR}/sbom-cyclonedx.json" ]; then
    echo "ERROR: ${RESULTS_DIR}/sbom-cyclonedx.json missing or empty" >&2
    echo "=== [Syft] validation FAILED ===" >&2
    exit 1
fi

if [ ! -s "${RESULTS_DIR}/sbom-spdx.json" ]; then
    echo "ERROR: ${RESULTS_DIR}/sbom-spdx.json missing or empty" >&2
    echo "=== [Syft] validation FAILED ===" >&2
    exit 1
fi

# Count components; zero means Syft produced an empty/broken SBOM.
COMPONENT_COUNT="$(python3 -c "
import json
d = json.load(open('${RESULTS_DIR}/sbom-cyclonedx.json'))
n = len(d.get('components', []))
print(n)
")"

echo "SBOM components found: ${COMPONENT_COUNT}"

if [ "${COMPONENT_COUNT}" -eq 0 ]; then
    echo "ERROR: SBOM has 0 components — Syft did not catalogue anything" >&2
    echo "=== [Syft] validation FAILED ===" >&2
    exit 1
fi

echo "SBOMs saved:"
echo "  ${RESULTS_DIR}/sbom-cyclonedx.json"
echo "  ${RESULTS_DIR}/sbom-spdx.json"
echo "=== [Syft] validation PASSED ==="
