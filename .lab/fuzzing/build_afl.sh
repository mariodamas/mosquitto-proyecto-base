#!/bin/sh
# build_afl.sh
# ------------
# Build all three fuzz harnesses with afl-clang-fast + ASan + UBSan.
# The analysis host must provide afl-clang-fast on PATH. This script does
# NOT install AFL++ — installation is the pipeline step's responsibility.
#
# Output: .lab/fuzzing/build/<harness>_afl
#
# MOSQUITTO_SRC defaults to the repo root.

set -eu

HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
MOSQUITTO_SRC="${MOSQUITTO_SRC:-$HERE/../..}"
BUILD_DIR="${BUILD_DIR:-$HERE/build}"
CC="${CC:-afl-clang-fast}"

# AFL++ reads these to compile sanitized builds. We set them here rather
# than at run time so the resulting binaries carry the instrumentation
# regardless of the caller environment.
AFL_USE_ASAN=1
AFL_USE_UBSAN=1
export AFL_USE_ASAN AFL_USE_UBSAN

# afl-clang-fast does not understand -fsanitize=fuzzer; it provides its
# own entry point glue via -DAFL_LIB when compiling a persistent harness.
# We keep LLVMFuzzerTestOneInput as the entry and use afl-compiler's
# built-in persistent-mode wrapper (-D_AFL_PERSISTENT, supplied by the
# afl_driver stub produced by afl-clang-fast when a fuzzer entry is
# present).
AFL_FLAGS="-g -O1"

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

mkdir -p "$BUILD_DIR"

# AFL's compiler generates its own main() driver when linking a TU that
# defines LLVMFuzzerTestOneInput and no main() — we rely on that behaviour.

# shellcheck disable=SC2086
"$CC" $AFL_FLAGS $COMMON_CFLAGS \
    "$HERE/harnesses/fuzz_packet_parser.c" \
    $LIB_TUS \
    -o "$BUILD_DIR/fuzz_packet_parser_afl"

# shellcheck disable=SC2086
"$CC" $AFL_FLAGS $COMMON_CFLAGS \
    "$HERE/harnesses/fuzz_bridge_remap.c" \
    $BROKER_TUS $LIB_TUS \
    -o "$BUILD_DIR/fuzz_bridge_remap_afl"

# shellcheck disable=SC2086
"$CC" $AFL_FLAGS $COMMON_CFLAGS -DLIBMOSQUITTO_STATIC \
    "$HERE/harnesses/fuzz_suback_client.c" \
    $CLIENT_SUBACK_TUS \
    -o "$BUILD_DIR/fuzz_suback_client_afl"

echo "AFL binaries:"
ls -1 "$BUILD_DIR"/*_afl 2>/dev/null || true
