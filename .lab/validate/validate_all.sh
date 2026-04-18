#!/bin/sh
# validate_all.sh
# ---------------
# Orchestrator: runs all 10 individual validation scripts in order and prints
# a summary table. Scripts that exit 0 due to SKIP (Coverity, EMBA) count as
# PASS in the summary. If any script exits non-zero the summary marks it FAIL
# but the orchestrator continues so all results are visible.
#
# Usage:
#   cd .lab/validate && sh validate_all.sh
#   sh .lab/validate/validate_all.sh
#
# Exit codes:
#   0  — all scripts passed (or skipped)
#   1  — one or more scripts failed

set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"

# RESULTS_DIR can be overridden by the caller (e.g. Jenkins sets WORKSPACE-relative path).
# Default: .lab/validate/results/ relative to this script.
RESULTS_DIR="${RESULTS_DIR:-${HERE}/results}"
export RESULTS_DIR

echo "========================================================"
echo " Mosquitto Lab — Full Validation Suite"
echo "========================================================"
echo ""

# ---------------------------------------------------------------------------
# Script list: (label, filename)
# ---------------------------------------------------------------------------
# We do not use arrays in POSIX sh; build a plain list of space-separated pairs
# and process them with a loop. Labels must not contain spaces.
SCRIPTS="
01_validate_secrets.sh         Gitleaks
02_validate_sast_codeql.sh     CodeQL
03_validate_sast_coverity.sh   Coverity
04_validate_sbom_syft.sh       Syft
05_validate_sca_grype.sh       Grype
06_validate_sca_snyk.sh        Snyk
07_validate_sca_emba.sh        EMBA
08_validate_fuzzing_libfuzzer.sh libFuzzer
09_validate_fuzzing_afl.sh     AFL++
10_validate_hardening.sh       Hardening
"

# Collect results: "script_file:PASS" or "script_file:FAIL".
RESULTS=""
ANY_FAIL=0

# Use a temp file to handle newlines in the scripts list portably.
TMPLIST="$(mktemp)"
printf '%s\n' "${SCRIPTS}" > "${TMPLIST}"

while IFS= read -r LINE; do
    # Skip blank lines.
    case "${LINE}" in
        ''|*[!\ ]*) ;;  # fall through to processing
    esac
    # Extract first token (script filename) and second token (label).
    SCRIPT_FILE="$(printf '%s' "${LINE}" | awk '{print $1}')"
    LABEL="$(printf '%s' "${LINE}" | awk '{print $2}')"

    # Skip blank / header lines from the heredoc.
    [ -z "${SCRIPT_FILE}" ] && continue
    [ -z "${LABEL}" ] && continue

    SCRIPT_PATH="${HERE}/${SCRIPT_FILE}"

    echo "--------------------------------------------------------"
    echo " Running: ${SCRIPT_FILE}"
    echo "--------------------------------------------------------"

    # Run the script; capture exit code without aborting on failure.
    set +e
    sh "${SCRIPT_PATH}"
    EXIT_CODE=$?
    set -e

    if [ "${EXIT_CODE}" -eq 0 ]; then
        RESULTS="${RESULTS}${LABEL}|PASS"$'\n'
    else
        RESULTS="${RESULTS}${LABEL}|FAIL"$'\n'
        ANY_FAIL=1
        echo "FAIL: ${SCRIPT_FILE} exited with code ${EXIT_CODE}" >&2
    fi

    echo ""
done < "${TMPLIST}"
rm -f "${TMPLIST}"

# ---------------------------------------------------------------------------
# Summary table
# ---------------------------------------------------------------------------
echo "========================================================"
echo " Summary"
echo "========================================================"
printf "%-28s | %s\n" "Script" "Result"
printf "%-28s-+-%s\n" "----------------------------" "------"

printf '%s' "${RESULTS}" | while IFS='|' read -r LABEL RESULT; do
    [ -z "${LABEL}" ] && continue
    printf "%-28s | %s\n" "${LABEL}" "${RESULT}"
done

echo "========================================================"

if [ "${ANY_FAIL}" -eq 0 ]; then
    echo "ALL VALIDATIONS PASSED"
    exit 0
else
    echo "ONE OR MORE VALIDATIONS FAILED — see output above" >&2
    exit 1
fi
