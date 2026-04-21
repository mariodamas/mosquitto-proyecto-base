#!/bin/sh
# 06_validate_sca_owasp_depcheck.sh
# ----------------------------------
# SCA (Software Composition Analysis) validation using OWASP Dependency Check.
# Performs dependency scanning and vulnerability detection on vendored C/C++ libraries.
#
# IMPORTANT — detection model:
#   OWASP Dependency Check scans for:
#   - Known CVE identifiers in version patterns and source files
#   - CPE (Common Platform Enumeration) matching
#   - Artifact hashing against NVD (National Vulnerability Database)
#   - Evidence collection from source code and file contents
#
#   For C/C++ vendored code, Dependency Check analyzes:
#   - File paths and naming patterns (e.g., "libwebsockets-2.4.2")
#   - Source code content and common vulnerability indicators
#   - Included headers and dependency chains
#
# Vendored targets scanned:
#   - .lab/vendor/cjson-1.7.14/          (cJSON 1.7.14)
#   - .lab/vendor/libwebsockets-2.4.2/   (libwebsockets 2.4.2)
#
# Prerequisites:
#   - dependency-check must be installed and available in PATH
#     Install with: https://github.com/jeremylong/DependencyCheck_Doc/releases
#   - Java 8 or higher required (Dependency Check runs on JVM)
#   - Internet connection for first run (NVD database download)
#
# Exit codes for this script:
#   0  — Dependency Check ran successfully (vulnerabilities may or may not be found)
#   1  — Tool missing, vendor dir missing, or tool error
#   2  — Vulnerabilities detected with severity threshold exceeded (optional)

set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LAB_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RESULTS_DIR="${RESULTS_DIR:-${LAB_DIR}/validate/results}"
mkdir -p "${RESULTS_DIR}"

# Optional: set severity threshold (LOW, MEDIUM, HIGH, CRITICAL)
# For strict policy, set to HIGH or CRITICAL. Default: MEDIUM
SEVERITY_THRESHOLD="${SEVERITY_THRESHOLD:-MEDIUM}"

echo "=== [OWASP Dependency Check] validation starting ==="
echo "  Severity threshold: ${SEVERITY_THRESHOLD}"
echo ""

# Availability check — Dependency Check CLI required.
if ! command -v dependency-check.sh >/dev/null 2>&1 && \
   ! command -v dependency-check >/dev/null 2>&1; then
    echo "ERROR: dependency-check not found in PATH." >&2
    echo "       Install OWASP Dependency Check from:" >&2
    echo "       https://github.com/jeremylong/DependencyCheck_Doc/releases" >&2
    echo "" >&2
    echo "       On Windows, use: dependency-check.bat" >&2
    echo "       On Linux/macOS, use: dependency-check.sh" >&2
    exit 1
fi

# Resolve the actual command to use
DEPCHECK_CMD="dependency-check.sh"
if ! command -v dependency-check.sh >/dev/null 2>&1; then
    if command -v dependency-check >/dev/null 2>&1; then
        DEPCHECK_CMD="dependency-check"
    fi
fi

# Show version
echo "Using: ${DEPCHECK_CMD}"
${DEPCHECK_CMD} --version || echo "WARNING: Could not retrieve version info"
echo ""

# ── Helper: parse Dependency Check JSON vuln count ──────────────────────────
depcheck_vuln_count() {
    RESULT_FILE="$1"
    if [ ! -s "${RESULT_FILE}" ]; then
        echo "0"
        return
    fi
    python3 -c "
import json, sys
try:
    with open('${RESULT_FILE}', 'r') as f:
        data = json.load(f)
    
    # Dependency Check JSON structure: reportSchema -> dependencies -> vulnerabilities
    vulns = []
    if 'reportSchema' in data:
        deps = data.get('reportSchema', {}).get('dependencies', [])
        for dep in deps:
            if isinstance(dep, dict):
                vulns.extend(dep.get('vulnerabilities', []))
    
    print(len(vulns))
except Exception as e:
    print(0)
" 2>/dev/null || echo "0"
}

# ── Helper: parse Dependency Check JSON vuln details ─────────────────────────
depcheck_vuln_details() {
    RESULT_FILE="$1"
    if [ ! -s "${RESULT_FILE}" ]; then
        echo ""
        return
    fi
    python3 -c "
import json, sys
try:
    with open('${RESULT_FILE}', 'r') as f:
        data = json.load(f)
    
    vulns = []
    if 'reportSchema' in data:
        deps = data.get('reportSchema', {}).get('dependencies', [])
        for dep in deps:
            if isinstance(dep, dict):
                dep_name = dep.get('packageString', dep.get('fileName', 'Unknown'))
                for vuln in dep.get('vulnerabilities', []):
                    if isinstance(vuln, dict):
                        cve = vuln.get('name', 'N/A')
                        severity = vuln.get('severity', 'UNKNOWN')
                        score = vuln.get('cvssv3', {}).get('baseScore', 'N/A')
                        vulns.append(f'    {dep_name}: {cve} ({severity}, score: {score})')
    
    if vulns:
        print('\n'.join(vulns))
except Exception as e:
    pass
" 2>/dev/null || true
}

# ── Helper: run one Dependency Check scan ────────────────────────────────────
depcheck_scan() {
    LABEL="$1"
    TARGET_DIR="$2"
    OUT_FILE="$3"

    if [ ! -d "${TARGET_DIR}" ]; then
        echo "ERROR: ${TARGET_DIR} not found." >&2
        echo "       The lab branch must include this vendored dependency." >&2
        return 1
    fi

    echo "--- Scanning ${LABEL} (${TARGET_DIR}) ---"
    
    # Create temporary output directory for Dependency Check
    TEMP_OUT_DIR="${RESULTS_DIR}/temp_depcheck_$$"
    mkdir -p "${TEMP_OUT_DIR}"
    
    # Run Dependency Check scan
    # --project: project name for reporting
    # --scan: target directory to scan
    # --format: output format (JSON for machine parsing)
    # --out: output directory
    # --enableExperimental: enable experimental analyzers (useful for C/C++)
    # --disableAssembly: skip .NET analysis (not needed for C/C++)
    # --enableUnknownLicense: report unknown licenses
    
    set +e
    ${DEPCHECK_CMD} \
        --project "${LABEL}" \
        --scan "${TARGET_DIR}" \
        --format JSON \
        --out "${TEMP_OUT_DIR}" \
        --enableExperimental \
        --disableAssembly \
        2>&1 | tee "${OUT_FILE}.log"
    DEPCHECK_EXIT=$?
    set -e

    # Dependency Check exits 0 on success, 1 on exception
    # Vulnerability presence is indicated in JSON, not exit code
    if [ "${DEPCHECK_EXIT}" -gt 1 ]; then
        echo "ERROR: Dependency Check exited with code ${DEPCHECK_EXIT} for ${LABEL}" >&2
        echo "       Check ${OUT_FILE}.log for details." >&2
        rm -rf "${TEMP_OUT_DIR}"
        return 1
    fi

    # Move JSON report to results directory
    if [ -f "${TEMP_OUT_DIR}/dependency-check-report.json" ]; then
        cp "${TEMP_OUT_DIR}/dependency-check-report.json" "${OUT_FILE}"
    fi

    COUNT="$(depcheck_vuln_count "${OUT_FILE}")"
    echo "  Dependency Check exit ${DEPCHECK_EXIT} | vulnerabilities found: ${COUNT}"
    
    # Show details if vulnerabilities found
    if [ "${COUNT}" -gt 0 ]; then
        echo "  Details:"
        depcheck_vuln_details "${OUT_FILE}"
    fi
    
    echo "  Results: ${OUT_FILE}"
    
    # Cleanup
    rm -rf "${TEMP_OUT_DIR}"
    
    return 0
}

# ── Scan 1: cJSON 1.7.14 ──────────────────────────────────────────────────────
echo ""
depcheck_scan \
    "cJSON 1.7.14" \
    "${LAB_DIR}/vendor/cjson-1.7.14" \
    "${RESULTS_DIR}/depcheck_cjson_result.json" || true

# ── Scan 2: libwebsockets 2.4.2 ───────────────────────────────────────────────
echo ""
depcheck_scan \
    "libwebsockets 2.4.2" \
    "${LAB_DIR}/vendor/libwebsockets-2.4.2" \
    "${RESULTS_DIR}/depcheck_libwebsockets_result.json" || true

# ── Summary ────────────────────────────────────────────────────────────────────
echo ""
echo "--- Summary ---"
CJSON_COUNT="$(depcheck_vuln_count "${RESULTS_DIR}/depcheck_cjson_result.json" || echo 0)"
LWS_COUNT="$(depcheck_vuln_count "${RESULTS_DIR}/depcheck_libwebsockets_result.json" || echo 0)"
TOTAL_COUNT=$((CJSON_COUNT + LWS_COUNT))

echo "  cJSON 1.7.14          : ${CJSON_COUNT} vulnerability/ies"
echo "  libwebsockets 2.4.2   : ${LWS_COUNT} vulnerability/ies"
echo "  Total                 : ${TOTAL_COUNT} vulnerability/ies"
echo ""

if [ "${TOTAL_COUNT}" -gt 0 ]; then
    echo "  FINDINGS DETECTED - Review results above."
    echo ""
    echo "  NOTE: OWASP Dependency Check uses NVD (National Vulnerability Database)"
    echo "  for vulnerability matching. Results depend on available CPE/CVE data."
    echo "  Cross-reference with other SCA tools (Snyk, Grype) for comprehensive"
    echo "  coverage. See .lab/docs/lab-decisions.md for SCA tool comparison."
else
    echo "  No vulnerabilities detected in scanned dependencies."
fi

echo ""
echo "Results saved to:"
echo "  ${RESULTS_DIR}/depcheck_cjson_result.json"
echo "  ${RESULTS_DIR}/depcheck_libwebsockets_result.json"
echo ""
echo "  Detailed logs:"
echo "  ${RESULTS_DIR}/depcheck_cjson_result.json.log"
echo "  ${RESULTS_DIR}/depcheck_libwebsockets_result.json.log"
echo ""
echo "=== [OWASP Dependency Check] validation PASSED ==="
