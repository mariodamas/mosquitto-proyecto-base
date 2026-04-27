#!/bin/sh
# build_libfuzzer.sh
# ------------------
# Build the enabled fuzz harnesses with libFuzzer + AddressSanitizer +
# UndefinedBehaviorSanitizer.
#
# Currently enabled harnesses (CI smoke build):
#   fuzz_packet_parser_libfuzzer  — broker-side MQTT property/packet parser
#   fuzz_bridge_remap_libfuzzer   — broker-side bridge inbound-topic remap
#
# Excluded harness (not compiled):
#   fuzz_suback_client            — client-side SUBACK parser; excluded because
#                                   its link closure is not yet minimal/stubbed.
#                                   Re-enable in run_campaigns.sh once the build
#                                   target is added here.
#
# IMPORTANT:
# - The analysis environment must provide clang on PATH.
# - This script does NOT install toolchain packages.
# - It assumes the Mosquitto source tree is available locally.
# - It assumes CMake configuration has already been run at least once
#   on the repo so that generated headers such as config.h exist.
#
# Output:
#   .lab/fuzzing/build/<harness>_libfuzzer
set -eu
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
MOSQUITTO_SRC="${MOSQUITTO_SRC:-$HERE/../..}"
BUILD_DIR="${BUILD_DIR:-$HERE/build}"
CC="${CC:-clang}"
FUZZ_FLAGS="-fsanitize=fuzzer,address,undefined -g -O1"
INCLUDE_FLAGS="-I$MOSQUITTO_SRC \
-I$MOSQUITTO_SRC/deps \
-I$MOSQUITTO_SRC/include \
-I$MOSQUITTO_SRC/lib \
-I$MOSQUITTO_SRC/src"
BROKER_CFLAGS="-DWITH_BROKER -DWITH_BRIDGE -DWITH_TLS=0 -DWITH_THREADING \
$INCLUDE_FLAGS"
PARSER_TUS="$MOSQUITTO_SRC/lib/property_mosq.c \
$MOSQUITTO_SRC/lib/packet_datatypes.c \
$MOSQUITTO_SRC/lib/memory_mosq.c \
$MOSQUITTO_SRC/lib/utf8_mosq.c \
$HERE/harnesses/stubs/log_stub.c"
BRIDGE_TUS="$MOSQUITTO_SRC/src/bridge_topic.c \
$MOSQUITTO_SRC/src/memory_public.c \
$MOSQUITTO_SRC/lib/memory_mosq.c \
$MOSQUITTO_SRC/lib/util_topic.c \
$HERE/harnesses/stubs/log_stub.c"
mkdir -p "$BUILD_DIR"
# fuzz_packet_parser — broker-side property parser path.
# shellcheck disable=SC2086
"$CC" $FUZZ_FLAGS $BROKER_CFLAGS \
   "$HERE/harnesses/fuzz_packet_parser.c" \
   $PARSER_TUS \
   -o "$BUILD_DIR/fuzz_packet_parser_libfuzzer"
# fuzz_bridge_remap — broker bridge rewrite path.
# shellcheck disable=SC2086
"$CC" $FUZZ_FLAGS $BROKER_CFLAGS \
   "$HERE/harnesses/fuzz_bridge_remap.c" \
   $BRIDGE_TUS \
   -o "$BUILD_DIR/fuzz_bridge_remap_libfuzzer"
echo "Enabled libFuzzer binaries:"
ls -1 "$BUILD_DIR"/*_libfuzzer 2>/dev/null || echo "  (none found)" >&2
