#!/bin/sh
# 09_validate_fuzzing_afl.sh
# --------------------------
# Smoke-test for AFL++: compile the fuzz_packet_parser harness with
# afl-clang-fast and run it for 30 seconds to confirm AFL++ starts,
# instruments correctly, and produces output. Follows the benchmark-fuzzing
# AFL++ pattern.
#
# Adaptation note (same as 08_validate_fuzzing_libfuzzer.sh):
#   Uses the full lib/ TU set from build_afl.sh rather than the spec's
#   simplified src/packet_mosq.c. Recorded in .lab/docs/lab-decisions.md.
#
# Exit codes:
#   0  — harness compiled, AFL++ ran for ~30 s, findings directory created
#   1  — afl-clang-fast missing, compile failed, or output dir not created

set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LAB_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RESULTS_DIR="${LAB_DIR}/validate/results"
mkdir -p "${RESULTS_DIR}"

MOSQUITTO_SRC="${MOSQUITTO_SRC:-${REPO_ROOT}}"

echo "=== [AFL++] validation starting ==="

# core_pattern check — AFL++ prints a hard error if this is not set to "core".
# We warn but do not abort; some systems (containers, WSL2) override this.
CORE_PATTERN="$(cat /proc/sys/kernel/core_pattern 2>/dev/null || echo unknown)"
if [ "${CORE_PATTERN}" != "core" ]; then
    echo "WARNING: core_pattern is '${CORE_PATTERN}', not 'core'."
    echo "         AFL++ may refuse to start without this setting."
    echo "         Fix with: echo core | sudo tee /proc/sys/kernel/core_pattern"
fi

# Availability check.
if ! command -v afl-clang-fast >/dev/null 2>&1; then
    echo "ERROR: afl-clang-fast not found. Run setup first." >&2
    exit 1
fi

afl-clang-fast --version 2>&1 | head -1 || true

HARNESS="${LAB_DIR}/fuzzing/harnesses/fuzz_packet_parser.c"
if [ ! -f "${HARNESS}" ]; then
    echo "ERROR: harness not found at ${HARNESS}" >&2
    exit 1
fi

CORPUS_DIR="${LAB_DIR}/fuzzing/corpus/mqtt"
if [ ! -d "${CORPUS_DIR}" ]; then
    echo "ERROR: corpus directory not found at ${CORPUS_DIR}" >&2
    exit 1
fi

echo "--- Compiling fuzz_packet_parser with afl-clang-fast + ASan + UBSan ---"
# AFL_USE_ASAN=1  : embed AddressSanitizer into the instrumented binary
# AFL_USE_UBSAN=1 : embed UndefinedBehaviorSanitizer into the binary
# These env vars are read by afl-clang-fast at compile time; they must be
# exported so the compiler wrapper sees them, not just the parent shell.
export AFL_USE_ASAN=1
export AFL_USE_UBSAN=1

# -g -O1 : debug info + light optimisation (AFL++ does not support -fsanitize=fuzzer)
# The same COMMON_CFLAGS as build_afl.sh mirror the upstream build macros.
afl-clang-fast -g -O1 \
    -DWITH_BROKER -DWITH_BRIDGE -DWITH_TLS=0 -DWITH_THREADING \
    "${HARNESS}" \
    "${MOSQUITTO_SRC}/lib/property_mosq.c" \
    "${MOSQUITTO_SRC}/lib/packet_datatypes.c" \
    "${MOSQUITTO_SRC}/lib/memory_mosq.c" \
    "${MOSQUITTO_SRC}/lib/util_mosq.c" \
    "${MOSQUITTO_SRC}/lib/util_topic.c" \
    "${MOSQUITTO_SRC}/lib/misc_mosq.c" \
    -I "${MOSQUITTO_SRC}/include/" \
    -I "${MOSQUITTO_SRC}/lib/" \
    -I "${MOSQUITTO_SRC}/src/" \
    -o "${RESULTS_DIR}/fuzz_packet_parser_afl_validate"

echo "Compile succeeded: ${RESULTS_DIR}/fuzz_packet_parser_afl_validate"

echo "--- Preparing isolated corpus for validation run ---"
# Copy corpus to a writable directory; AFL++ may mutate seeds in-place.
mkdir -p "${RESULTS_DIR}/afl_validate_corpus"
cp "${CORPUS_DIR}/"* "${RESULTS_DIR}/afl_validate_corpus/"

echo "--- Running AFL++ for ~30 seconds (validation run) ---"
# AFL_NO_UI=1       : disable the interactive ncurses UI; required in CI / non-tty
# AFL_SKIP_CPUFREQ=1: skip the CPU-frequency governor check that AFL++ enforces
#                     on bare-metal hosts; avoids a hard abort on cloud VMs
# -i : input corpus directory
# -o : output/findings directory
# -t 1000 : per-test-case timeout in ms (1 s; Mosquitto parsing is fast)
# @@ : AFL++ replaces @@ with the path to the current mutated input file
# timeout 35 ... || true : AFL++ exits non-zero when killed by timeout;
#   we use || true and check the output directory instead of the exit code.
AFL_NO_UI=1 AFL_SKIP_CPUFREQ=1 \
timeout 35 afl-fuzz \
    -i "${RESULTS_DIR}/afl_validate_corpus/" \
    -o "${RESULTS_DIR}/afl_validate_findings/" \
    -t 1000 \
    -- "${RESULTS_DIR}/fuzz_packet_parser_afl_validate" @@ \
    2>&1 | tee "${RESULTS_DIR}/afl_validate.log" || true

echo "--- Verifying AFL++ produced output ---"
if [ ! -d "${RESULTS_DIR}/afl_validate_findings" ]; then
    echo "ERROR: AFL++ findings directory not created" >&2
    echo "=== [AFL++] validation FAILED ===" >&2
    exit 1
fi

# AFL++ creates at minimum a default/queue subdirectory with processed seeds.
QUEUE_COUNT="$(find "${RESULTS_DIR}/afl_validate_findings" -type f | wc -l)"
if [ "${QUEUE_COUNT}" -eq 0 ]; then
    echo "ERROR: AFL++ findings directory is empty — fuzzer may not have started" >&2
    echo "       Check ${RESULTS_DIR}/afl_validate.log for details." >&2
    echo "=== [AFL++] validation FAILED ===" >&2
    exit 1
fi

echo "AFL++ produced ${QUEUE_COUNT} file(s) in findings directory"
echo "Log saved to ${RESULTS_DIR}/afl_validate.log"
echo "=== [AFL++] validation PASSED ==="
