#!/bin/sh
# 05_validate_sca_grype.sh
# ------------------------
# Smoke-test for Grype: scan the CycloneDX SBOM produced by
# 04_validate_sbom_syft.sh and also the hand-curated vendor manifest
# at .lab/sca/vendor-manifest.cdx.json.
#
# Why two scans?
#   Automated SBOM tools (Syft, Snyk --unmanaged) cannot detect vendored
#   C/C++ headers or source-only dependencies without a package manifest.
#   The vendor manifest provides the curated component list so Grype can
#   look up CVEs against the correct purl coordinates. This is the industry
#   standard practice for embedded C/C++ SCA (see .lab/docs/lab-decisions.md).
#
# Prerequisites:
#   Run 04_validate_sbom_syft.sh first to produce sbom-cyclonedx.json.
#   Vendor manifest must exist at .lab/sca/vendor-manifest.cdx.json.
#
# Note: Grype may find 0 vulnerabilities in the Syft SBOM — this is expected
# and is a PASS. The vendor manifest scan is where CVE findings are expected.
#
# Exit codes:
#   0  — both Grype scans ran and produced parseable JSON output
#   1  — tool missing, SBOM/manifest not found, or JSON output malformed

set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LAB_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RESULTS_DIR="${RESULTS_DIR:-${LAB_DIR}/validate/results}"
mkdir -p "${RESULTS_DIR}"

VENDOR_MANIFEST="${LAB_DIR}/sca/vendor-manifest.cdx.json"

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

# Vendor manifest must exist.
if [ ! -f "${VENDOR_MANIFEST}" ]; then
    echo "ERROR: vendor manifest not found at ${VENDOR_MANIFEST}" >&2
    echo "       The lab branch must include .lab/sca/vendor-manifest.cdx.json" >&2
    exit 1
fi

# ── Scan 1: Syft SBOM ────────────────────────────────────────────────────────
echo "--- Scan 1/2: Grype on Syft SBOM (automated component list) ---"
# sbom: prefix tells Grype to read an existing SBOM rather than scan a target.
# --output json  : machine-readable output for post-run parsing and Jenkins.
grype sbom:"${RESULTS_DIR}/sbom-cyclonedx.json" \
    --output json > "${RESULTS_DIR}/grype_result.json"

echo "--- Grype human-readable table (Syft SBOM) ---"
grype sbom:"${RESULTS_DIR}/sbom-cyclonedx.json" \
    --output table

if [ ! -s "${RESULTS_DIR}/grype_result.json" ]; then
    echo "ERROR: ${RESULTS_DIR}/grype_result.json missing or empty" >&2
    echo "=== [Grype] validation FAILED ===" >&2
    exit 1
fi

SYFT_MATCHES="$(python3 -c "
import json
d = json.load(open('${RESULTS_DIR}/grype_result.json'))
n = len(d.get('matches', []))
print(n)
")"
echo "Grype (Syft SBOM) vulnerabilities found: ${SYFT_MATCHES}"
echo "  (0 is expected — Syft cannot enumerate vendored C/C++ components)"

# ── Scan 2: Vendor manifest ───────────────────────────────────────────────────
echo "--- Scan 2/2: Grype on vendor manifest (curated component list) ---"
grype sbom:"${VENDOR_MANIFEST}" \
    --output json > "${RESULTS_DIR}/grype_vendor_result.json"

echo "--- Grype human-readable table (vendor manifest) ---"
grype sbom:"${VENDOR_MANIFEST}" \
    --output table

if [ ! -s "${RESULTS_DIR}/grype_vendor_result.json" ]; then
    echo "ERROR: ${RESULTS_DIR}/grype_vendor_result.json missing or empty" >&2
    echo "=== [Grype] validation FAILED ===" >&2
    exit 1
fi

VENDOR_MATCHES="$(python3 -c "
import json
d = json.load(open('${RESULTS_DIR}/grype_vendor_result.json'))
matches = d.get('matches', [])
n = len(matches)
if n > 0:
    for m in matches[:5]:
        vuln = m.get('vulnerability', {})
        pkg  = m.get('artifact', {})
        print(f'  {vuln.get(\"id\",\"?\")} [{vuln.get(\"severity\",\"?\")}] — {pkg.get(\"name\",\"?\")} {pkg.get(\"version\",\"?\")}')
    if n > 5:
        print(f'  ... and {n - 5} more')
print(n)
" | tail -1)"

echo "Grype (vendor manifest) vulnerabilities found: ${VENDOR_MATCHES}"

# ── Summary ───────────────────────────────────────────────────────────────────
echo "--- Summary ---"
echo "  Syft SBOM scan   : ${SYFT_MATCHES} match(es)  — expected 0 (structural gap)"
echo "  Vendor manifest  : ${VENDOR_MATCHES} match(es)  — CVE detection via curated SBOM"

echo "Grype findings saved to:"
echo "  ${RESULTS_DIR}/grype_result.json        (Syft SBOM)"
echo "  ${RESULTS_DIR}/grype_vendor_result.json (vendor manifest)"
echo "=== [Grype] validation PASSED ==="
