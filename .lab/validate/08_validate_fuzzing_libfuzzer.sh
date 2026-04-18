#!/bin/sh
# 08_validate_fuzzing_libfuzzer.sh
# ---------------------------------
# Smoke-test for clang/libFuzzer: compile the fuzz_packet_parser harness and
# run it for 30 seconds to confirm the fuzzer starts, executes test cases, and
# produces exec/s > 0. Follows the benchmark-fuzzing libFuzzer pattern.
#
# Adaptation note (per spec 08 "Note from benchmark-fuzzing"):
#   The spec lists src/packet_mosq.c as the only extra TU. However, the harness
#   uses property__read_all and related symbols that live in the lib/ TUs used
#   by build_libfuzzer.sh. For this smoke-test we keep a minimal parser-focused
#   TU set and add a tiny log stub, avoiding unrelated broker/network deps.
#   This deviation is recorded in .lab/docs/lab-decisions.md.
#
# Variables:
#   MOSQUITTO_SRC  : override repo root (default: auto-detected from script path)
#
# Exit codes:
#   0  - harness compiled, ran for 30 s, exec/s > 0
#   1  - clang missing, compile failed, or fuzzer produced no executions

set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LAB_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RESULTS_DIR="${LAB_DIR}/validate/results"
mkdir -p "${RESULTS_DIR}"

# Allow callers to override the Mosquitto source root.
MOSQUITTO_SRC="${MOSQUITTO_SRC:-${REPO_ROOT}}"

echo "=== [libFuzzer] validation starting ==="

# Availability check.
if ! command -v clang >/dev/null 2>&1; then
    echo "ERROR: clang not found. Run setup first." >&2
    exit 1
fi

clang --version | head -1

HARNESS="${LAB_DIR}/fuzzing/harnesses/fuzz_packet_parser.c"
if [ ! -f "${HARNESS}" ]; then
    echo "ERROR: harness not found at ${HARNESS}" >&2
    exit 1
fi

LOG_STUB="${LAB_DIR}/fuzzing/harnesses/fuzz_log_stub.c"
if [ ! -f "${LOG_STUB}" ]; then
    echo "ERROR: log stub not found at ${LOG_STUB}" >&2
    exit 1
fi

CORPUS_DIR="${LAB_DIR}/fuzzing/corpus/mqtt"
if [ ! -d "${CORPUS_DIR}" ]; then
    echo "ERROR: corpus directory not found at ${CORPUS_DIR}" >&2
    exit 1
fi

mkdir -p "${RESULTS_DIR}/libfuzzer_artifacts"

echo "--- Compiling fuzz_packet_parser with libFuzzer + ASan + UBSan ---"
# -fsanitize=fuzzer    : links the libFuzzer engine and its main() driver
# -fsanitize=address   : AddressSanitizer - catches heap/stack buffer overflows
# -fsanitize=undefined : UndefinedBehaviorSanitizer - catches integer overflows etc.
# -g -O1               : debug info + minimal optimisation (standard for fuzz builds)
# -DWITH_BROKER etc.   : mirror the macros used by the upstream build so private
#                        headers compile without missing-declaration errors
# Keep link closure limited to parser-related code paths.
clang -fsanitize=fuzzer,address,undefined -g -O1 \
    -DWITH_BROKER -DWITH_BRIDGE -DWITH_TLS=0 -DWITH_THREADING \
    "${HARNESS}" \
    "${MOSQUITTO_SRC}/lib/property_mosq.c" \
    "${MOSQUITTO_SRC}/lib/packet_datatypes.c" \
    "${MOSQUITTO_SRC}/lib/memory_mosq.c" \
    "${MOSQUITTO_SRC}/lib/utf8_mosq.c" \
    "${LOG_STUB}" \
    -I "${MOSQUITTO_SRC}/" \
    -I "${MOSQUITTO_SRC}/deps/" \
    -I "${MOSQUITTO_SRC}/include/" \
    -I "${MOSQUITTO_SRC}/lib/" \
    -I "${MOSQUITTO_SRC}/src/" \
    -o "${RESULTS_DIR}/fuzz_packet_parser_validate"

echo "Compile succeeded: ${RESULTS_DIR}/fuzz_packet_parser_validate"

echo "--- Running libFuzzer for 30 seconds (validation run) ---"
# -max_total_time=30      : hard stop after 30 s; this is a smoke-test, not a campaign
# -print_final_stats=1    : dump exec/s and other counters on exit (we parse these)
# -artifact_prefix        : write any crash inputs here, isolated from campaign outputs
# Corpus is read-only in validation mode (no -merge, no new seed writing).
"${RESULTS_DIR}/fuzz_packet_parser_validate" \
    -max_total_time=30 \
    -print_final_stats=1 \
    -artifact_prefix="${RESULTS_DIR}/libfuzzer_artifacts/" \
    "${CORPUS_DIR}" \
    2>&1 | tee "${RESULTS_DIR}/libfuzzer_validate.log"

echo "--- Verifying fuzzer produced executions ---"
# final_stats line looks like: "stat::number_of_executed_units: 12345"
EXEC_COUNT="$(grep -E 'number_of_executed_units' \
    "${RESULTS_DIR}/libfuzzer_validate.log" | \
    grep -oE '[0-9]+$' || echo 0)"

echo "libFuzzer executions: ${EXEC_COUNT}"

if [ "${EXEC_COUNT}" -eq 0 ]; then
    echo "ERROR: fuzzer ran but executed 0 units - something went wrong" >&2
    echo "=== [libFuzzer] validation FAILED ===" >&2
    exit 1
fi

echo "Log saved to ${RESULTS_DIR}/libfuzzer_validate.log"
echo "=== [libFuzzer] validation PASSED ==="
