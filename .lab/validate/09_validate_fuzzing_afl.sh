#!/bin/sh
# 09_validate_fuzzing_afl.sh
# --------------------------
# Smoke-test for AFL++: compile the fuzz_packet_parser harness with
# afl-clang-fast and run it for 30 seconds to confirm AFL++ starts,
# instruments correctly, and produces output. Follows the benchmark-fuzzing
# AFL++ pattern.
#
# Adaptation note (same as 08_validate_fuzzing_libfuzzer.sh):
#   Uses a minimal parser-focused TU set plus a tiny logger stub to keep
#   link closure stable for standalone harness validation.
#
# Exit codes:
#   0  - harness compiled, AFL++ ran for ~30 s, findings directory created
#   1  - afl-clang-fast missing, compile failed, or output dir not created

set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LAB_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RESULTS_DIR="${LAB_DIR}/validate/results"
mkdir -p "${RESULTS_DIR}"

MOSQUITTO_SRC="${MOSQUITTO_SRC:-${REPO_ROOT}}"

echo "=== [AFL++] validation starting ==="

# core_pattern check - AFL++ can hard-fail when this is not "core".
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

echo "--- Compiling fuzz_packet_parser with afl-clang-fast + ASan + UBSan ---"
# AFL_USE_ASAN=1  : embed AddressSanitizer into the instrumented binary
# AFL_USE_UBSAN=1 : embed UndefinedBehaviorSanitizer into the binary
export AFL_USE_ASAN=1
export AFL_USE_UBSAN=1

AFL_DRIVER="${RESULTS_DIR}/afl_file_driver_validate.c"
cat > "${AFL_DRIVER}" <<'EOF'
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size);

int main(int argc, char **argv)
{
    FILE *f;
    long sz;
    uint8_t *buf;
    size_t n;

    if(argc < 2){
        return 0;
    }

    f = fopen(argv[1], "rb");
    if(!f){
        return 0;
    }

    if(fseek(f, 0, SEEK_END) != 0){
        fclose(f);
        return 0;
    }

    sz = ftell(f);
    if(sz < 0){
        fclose(f);
        return 0;
    }

    if(fseek(f, 0, SEEK_SET) != 0){
        fclose(f);
        return 0;
    }

    if(sz == 0){
        fclose(f);
        return LLVMFuzzerTestOneInput(NULL, 0);
    }

    buf = (uint8_t *)malloc((size_t)sz);
    if(!buf){
        fclose(f);
        return 0;
    }

    n = fread(buf, 1, (size_t)sz, f);
    fclose(f);

    LLVMFuzzerTestOneInput(buf, n);
    free(buf);
    return 0;
}
EOF

afl-clang-fast -g -O1 \
    -DWITH_BROKER -DWITH_BRIDGE -DWITH_TLS=0 -DWITH_THREADING \
    "${AFL_DRIVER}" \
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
    -o "${RESULTS_DIR}/fuzz_packet_parser_afl_validate"

echo "Compile succeeded: ${RESULTS_DIR}/fuzz_packet_parser_afl_validate"

echo "--- Preparing isolated corpus for validation run ---"
rm -rf "${RESULTS_DIR}/afl_validate_corpus" "${RESULTS_DIR}/afl_validate_findings"
mkdir -p "${RESULTS_DIR}/afl_validate_corpus"
cp "${CORPUS_DIR}/"* "${RESULTS_DIR}/afl_validate_corpus/"

echo "--- Running AFL++ for ~30 seconds (validation run) ---"
# AFL_NO_UI=1       : disable interactive ncurses UI for non-tty runs
# AFL_SKIP_CPUFREQ=1: skip CPU governor strictness checks
# AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1: bypass core_pattern hard stop
# timeout 35 ... || true : AFL++ exits non-zero when killed by timeout
AFL_NO_UI=1 AFL_SKIP_CPUFREQ=1 AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1 \
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

QUEUE_COUNT="$(find "${RESULTS_DIR}/afl_validate_findings" -type f | wc -l | tr -d '[:space:]')"
if [ -z "${QUEUE_COUNT}" ]; then
    QUEUE_COUNT="0"
fi

if [ "${QUEUE_COUNT}" -eq 0 ]; then
    echo "ERROR: AFL++ findings directory is empty - fuzzer may not have started" >&2
    echo "       Check ${RESULTS_DIR}/afl_validate.log for details." >&2
    echo "=== [AFL++] validation FAILED ===" >&2
    exit 1
fi

echo "AFL++ produced ${QUEUE_COUNT} file(s) in findings directory"
echo "Log saved to ${RESULTS_DIR}/afl_validate.log"
echo "=== [AFL++] validation PASSED ==="
