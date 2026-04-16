#!/bin/sh
# measure_coverage.sh
# -------------------
# Build instrumented versions of each harness with LLVM source-based
# coverage, replay the current corpus, and emit both a text summary and
# an HTML coverage report. The pipeline uploads the HTML dir as an
# artefact for the coverage phase.
#
# Tools required on PATH: clang, llvm-profdata, llvm-cov.
# This script does NOT install anything.

set -eu

HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
MOSQUITTO_SRC="${MOSQUITTO_SRC:-$HERE/../..}"
BUILD_DIR="${BUILD_DIR:-$HERE/build/coverage}"
COV_DIR="${COV_DIR:-$HERE/coverage}"
CC="${CC:-clang}"

# Same TU sets as build_libfuzzer.sh, but instrumented for coverage instead
# of libFuzzer. We still link a libFuzzer driver because the harnesses use
# LLVMFuzzerTestOneInput as their entry; libFuzzer is then driven once per
# corpus file (-runs=0) to collect coverage rather than fuzz.
COV_FLAGS="-fsanitize=fuzzer,address -fprofile-instr-generate -fcoverage-mapping -g -O1"

COMMON_CFLAGS="-DWITH_BROKER -DWITH_BRIDGE -DWITH_TLS=0 -DWITH_THREADING \
-I$MOSQUITTO_SRC/include -I$MOSQUITTO_SRC/lib -I$MOSQUITTO_SRC/src"

LIB_TUS="$MOSQUITTO_SRC/lib/property_mosq.c \
         $MOSQUITTO_SRC/lib/packet_datatypes.c \
         $MOSQUITTO_SRC/lib/memory_mosq.c \
         $MOSQUITTO_SRC/lib/util_mosq.c \
         $MOSQUITTO_SRC/lib/util_topic.c \
         $MOSQUITTO_SRC/lib/misc_mosq.c"

BROKER_TUS="$MOSQUITTO_SRC/src/bridge_topic.c \
            $MOSQUITTO_SRC/src/memory_public.c"

CLIENT_SUBACK_TUS="$MOSQUITTO_SRC/lib/handle_suback.c \
                   $MOSQUITTO_SRC/lib/messages_mosq.c \
                   $MOSQUITTO_SRC/lib/property_mosq.c \
                   $MOSQUITTO_SRC/lib/packet_datatypes.c \
                   $MOSQUITTO_SRC/lib/memory_mosq.c"

mkdir -p "$BUILD_DIR" "$COV_DIR"

# Build instrumented binaries.
# shellcheck disable=SC2086
"$CC" $COV_FLAGS $COMMON_CFLAGS \
    "$HERE/harnesses/fuzz_packet_parser.c" \
    $LIB_TUS \
    -o "$BUILD_DIR/fuzz_packet_parser_cov"

# shellcheck disable=SC2086
"$CC" $COV_FLAGS $COMMON_CFLAGS \
    "$HERE/harnesses/fuzz_bridge_remap.c" \
    $BROKER_TUS $LIB_TUS \
    -o "$BUILD_DIR/fuzz_bridge_remap_cov"

# shellcheck disable=SC2086
"$CC" $COV_FLAGS $COMMON_CFLAGS -DLIBMOSQUITTO_STATIC \
    "$HERE/harnesses/fuzz_suback_client.c" \
    $CLIENT_SUBACK_TUS \
    -o "$BUILD_DIR/fuzz_suback_client_cov"

# Replay each corpus against each binary to produce .profraw files.
replay() {
    _bin="$1"
    _name="$2"
    _corpus="$3"
    LLVM_PROFILE_FILE="$COV_DIR/${_name}.profraw" \
        "$_bin" "$_corpus" -runs=0 \
        >"$COV_DIR/${_name}.runlog" 2>&1 || true
}

replay "$BUILD_DIR/fuzz_packet_parser_cov" fuzz_packet_parser "$HERE/corpus/mqtt"
replay "$BUILD_DIR/fuzz_bridge_remap_cov"  fuzz_bridge_remap  "$HERE/corpus/mqtt"
replay "$BUILD_DIR/fuzz_suback_client_cov" fuzz_suback_client "$HERE/corpus/mqtt"

# Merge profraw -> profdata and render reports.
llvm-profdata merge -sparse \
    "$COV_DIR"/*.profraw \
    -o "$COV_DIR/merged.profdata"

# Text summary for pipeline parsing.
for h in fuzz_packet_parser fuzz_bridge_remap fuzz_suback_client; do
    llvm-cov report \
        "$BUILD_DIR/${h}_cov" \
        -instr-profile="$COV_DIR/merged.profdata" \
        > "$COV_DIR/${h}.report.txt" || true
done

# HTML report bundled for artefact upload.
llvm-cov show \
    "$BUILD_DIR/fuzz_packet_parser_cov" \
    -instr-profile="$COV_DIR/merged.profdata" \
    -format=html -output-dir="$COV_DIR/html" \
    -show-line-counts-or-regions || true

echo "coverage output: $COV_DIR"
