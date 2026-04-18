#!/bin/sh
# 06_validate_sca_snyk.sh
# -----------------------
# Smoke-test for Snyk CLI in --unmanaged mode: fingerprint-scan each
# vendored C/C++ dependency for known CVEs.
#
# IMPORTANT — detection model:
#   Snyk --unmanaged uses source code fingerprinting against Snyk's OSS DB.
#   It does NOT read CycloneDX/SPDX manifests. The vendor manifest at
#   .lab/sca/vendor-manifest.cdx.json is consumed by Grype (stage 05), not Snyk.
#   If a library's source is not in Snyk's fingerprint database, Snyk will
#   report 0 vulnerabilities — this is a known limitation, not a tool error,
#   and is documented as a pipeline-risk finding in lab-decisions.md.
#
# Vendored targets scanned:
#   - .lab/vendor/cjson-1.7.14/          (cJSON 1.7.14)
#   - .lab/vendor/libwebsockets-2.4.2/   (libwebsockets 2.4.2)
#
# Prerequisites:
#   SNYK_TOKEN environment variable must be set to a valid Snyk API token.
#
# Exit codes for this script:
#   0  — Snyk ran against all vendor dirs (0 or 1 from each run = PASS)
#   1  — SNYK_TOKEN missing, vendor dir missing, or Snyk tool error (exit >1)

set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LAB_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RESULTS_DIR="${RESULTS_DIR:-${LAB_DIR}/validate/results}"
mkdir -p "${RESULTS_DIR}"

echo "=== [Snyk] validation starting ==="

# Normalize token to avoid CRLF/header issues when sourced from Windows .env files.
SNYK_TOKEN_CLEAN="$(printf '%s' "${SNYK_TOKEN:-}" | tr -d '\r\n')"
export SNYK_TOKEN="${SNYK_TOKEN_CLEAN}"

# Token check — Snyk CLI requires authentication; fail early with a clear message.
if [ -z "${SNYK_TOKEN}" ]; then
    echo "ERROR: SNYK_TOKEN environment variable not set." >&2
    echo "       Export a valid Snyk API token before running this script." >&2
    exit 1
fi

# Availability check.
if ! command -v snyk >/dev/null 2>&1; then
    echo "ERROR: snyk not found. Run setup first." >&2
    exit 1
fi

snyk --version

# ── Helper: parse Snyk JSON vuln count ───────────────────────────────────────
snyk_vuln_count() {
    RESULT_FILE="$1"
    if [ ! -s "${RESULT_FILE}" ]; then
        echo "0"
        return
    fi
    python3 -c "
import json, sys
try:
    d = json.load(open('${RESULT_FILE}'))
    def vuln_count(obj):
        if isinstance(obj, dict):
            v = obj.get('vulnerabilities') or obj.get('issues')
            return len(v) if isinstance(v, list) else 0
        return sum(vuln_count(i) for i in obj) if isinstance(obj, list) else 0
    print(vuln_count(d))
except Exception as e:
    print(0)
" 2>/dev/null || echo "0"
}

# ── Helper: run one Snyk --unmanaged scan ────────────────────────────────────
snyk_scan() {
    LABEL="$1"
    TARGET_DIR="$2"
    OUT_FILE="$3"

    if [ ! -d "${TARGET_DIR}" ]; then
        echo "ERROR: ${TARGET_DIR} not found." >&2
        echo "       The lab branch must include this vendored dependency." >&2
        return 1
    fi

    echo "--- Scanning ${LABEL} (${TARGET_DIR}) ---"
    # --unmanaged : fingerprint-based scan for C/C++ vendored code.
    # Snyk exits 0 (no vulns) or 1 (vulns found) — both are PASS.
    # Exit >1 is a tool error — propagate as failure.
    set +e
    snyk test --unmanaged "${TARGET_DIR}" \
        --json > "${OUT_FILE}" 2>&1
    SNYK_EXIT=$?
    set -e

    if [ "${SNYK_EXIT}" -gt 1 ]; then
        echo "ERROR: Snyk exited with code ${SNYK_EXIT} for ${LABEL}" >&2
        echo "       Check ${OUT_FILE} for details." >&2
        return 1
    fi

    COUNT="$(snyk_vuln_count "${OUT_FILE}")"
    echo "  Snyk exit ${SNYK_EXIT} | vulnerabilities found: ${COUNT}"
    echo "  Results: ${OUT_FILE}"
    return 0
}

# ── Scan 1: cJSON 1.7.14 ─────────────────────────────────────────────────────
echo ""
snyk_scan \
    "cJSON 1.7.14" \
    "${LAB_DIR}/vendor/cjson-1.7.14" \
    "${RESULTS_DIR}/snyk_cjson_result.json"

# ── Scan 2: libwebsockets 2.4.2 ──────────────────────────────────────────────
echo ""
snyk_scan \
    "libwebsockets 2.4.2" \
    "${LAB_DIR}/vendor/libwebsockets-2.4.2" \
    "${RESULTS_DIR}/snyk_libwebsockets_result.json"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "--- Summary ---"
CJSON_COUNT="$(snyk_vuln_count "${RESULTS_DIR}/snyk_cjson_result.json")"
LWS_COUNT="$(snyk_vuln_count "${RESULTS_DIR}/snyk_libwebsockets_result.json")"
echo "  cJSON 1.7.14          : ${CJSON_COUNT} vulnerability/ies"
echo "  libwebsockets 2.4.2   : ${LWS_COUNT} vulnerability/ies"
echo ""
echo "  NOTE: 0 findings may indicate library not in Snyk's fingerprint DB."
echo "  This is a known C/C++ SCA limitation — see .lab/docs/lab-decisions.md."
echo "  CVE detection for these components is provided by Grype (stage 05)"
echo "  via the curated vendor manifest at .lab/sca/vendor-manifest.cdx.json."
echo ""
echo "Results saved to:"
echo "  ${RESULTS_DIR}/snyk_cjson_result.json"
echo "  ${RESULTS_DIR}/snyk_libwebsockets_result.json"
echo "=== [Snyk] validation PASSED ==="
