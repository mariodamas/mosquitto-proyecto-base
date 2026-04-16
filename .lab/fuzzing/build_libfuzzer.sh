#!/bin/sh
# build_libfuzzer.sh
# ------------------
# Build all three fuzz harnesses with libFuzzer + AddressSanitizer +
# UndefinedBehaviorSanitizer. The analysis host must provide clang on PATH.
# This script does NOT install toolchain packages — installation is the
# pipeline step's responsibility.
#
# Output: .lab/fuzzing/build/<harness>_libfuzzer
#
# MOSQUITTO_SRC defaults to the repo root relative to this script, so a
# fresh checkout of the lab branch works without further configuration.

set -eu

HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
MOSQUITTO_SRC="${MOSQUITTO_SRC:-$HERE/../..}"
BUILD_DIR="${BUILD_DIR:-$HERE/build}"
CC="${CC:-clang}"

# Sanitizer set is fixed on purpose: the pipeline compares runs across
# harnesses, so changing flags would invalidate the comparison.
FUZZ_FLAGS="-fsanitize=fuzzer,address,undefined -g -O1"

# Mosquitto build macros: we mimic the defaults used by the upstream
# Makefile/CMake so private headers compile. WITH_TLS=0 keeps link closure
# minimal for the packet/property parser harness; the bridge harness needs
# the same set.
COMMON_CFLAGS="-DWITH_BROKER -DWITH_BRIDGE -DWITH_TLS=0 -DWITH_THREADING \
-I$MOSQUITTO_SRC/include -I$MOSQUITTO_SRC/lib -I$MOSQUITTO_SRC/src"

# The TU set mirrors the functions each harness reaches. We compile each
# harness as its own binary to keep link sets small and errors localised.
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

mkdir -p "$BUILD_DIR"

# fuzz_packet_parser — broker-side property parser path.
# shellcheck disable=SC2086
"$CC" $FUZZ_FLAGS $COMMON_CFLAGS \
    "$HERE/harnesses/fuzz_packet_parser.c" \
    $LIB_TUS \
    -o "$BUILD_DIR/fuzz_packet_parser_libfuzzer"

# fuzz_bridge_remap — broker bridge rewrite path.
# shellcheck disable=SC2086
"$CC" $FUZZ_FLAGS $COMMON_CFLAGS \
    "$HERE/harnesses/fuzz_bridge_remap.c" \
    $BROKER_TUS $LIB_TUS \
    -o "$BUILD_DIR/fuzz_bridge_remap_libfuzzer"

# fuzz_suback_client — libmosquitto client SUBACK parser.
# shellcheck disable=SC2086
"$CC" $FUZZ_FLAGS $COMMON_CFLAGS -DLIBMOSQUITTO_STATIC \
    "$HERE/harnesses/fuzz_suback_client.c" \
    $CLIENT_SUBACK_TUS \
    -o "$BUILD_DIR/fuzz_suback_client_libfuzzer"

echo "libFuzzer binaries:"
ls -1 "$BUILD_DIR"/*_libfuzzer 2>/dev/null || true
