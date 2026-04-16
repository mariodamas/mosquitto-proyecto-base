#!/bin/sh
# run_campaigns.sh
# ----------------
# Run fuzzing campaigns against each harness for a bounded time budget.
# First positional argument selects the engine: "libfuzzer" or "afl".
# CAMPAIGN_TIME controls the per-harness wall-clock budget in seconds
# (default 1800 = 30 minutes), matching the pipeline's default slice.
#
# Logs/crashes go under .lab/fuzzing/findings/<engine>/<harness>/.
# This script does not install tools and does not orchestrate CI.

set -eu

HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
BUILD_DIR="${BUILD_DIR:-$HERE/build}"
FINDINGS_DIR="${FINDINGS_DIR:-$HERE/findings}"
CORPUS_MQTT="$HERE/corpus/mqtt"
CORPUS_CJSON="$HERE/corpus/cjson"
CAMPAIGN_TIME="${CAMPAIGN_TIME:-1800}"
ENGINE="${1:-libfuzzer}"

if [ "$ENGINE" != "libfuzzer" ] && [ "$ENGINE" != "afl" ]; then
    echo "usage: $0 {libfuzzer|afl}" >&2
    exit 2
fi

# AFL++ refuses to start if the host's core_pattern pipes cores to an
# external handler (systemd-coredump etc.). Root is required to fix it.
# We print the reminder instead of silently tweaking a host-wide sysctl.
if [ "$ENGINE" = "afl" ]; then
    cat >&2 <<'EOF'
[run_campaigns] AFL++ host-side note:
  Before starting, confirm /proc/sys/kernel/core_pattern does not begin with "|".
  Fix (requires root):
      echo core | sudo tee /proc/sys/kernel/core_pattern
  Or, for informational runs only, export:
      AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1
EOF
fi

mkdir -p "$FINDINGS_DIR/libfuzzer" "$FINDINGS_DIR/afl"

run_libfuzzer() {
    _bin="$1"
    _name="$2"
    _seed_dir="$3"
    _out="$FINDINGS_DIR/libfuzzer/$_name"
    mkdir -p "$_out/corpus" "$_out/crashes"

    # Copy seeds into the run corpus. libFuzzer mutates the corpus in place,
    # so we do not want to modify the canonical seed directory.
    if [ -d "$_seed_dir" ]; then
        cp -r "$_seed_dir"/. "$_out/corpus/" 2>/dev/null || true
    fi

    echo "[libfuzzer] $_name  budget=${CAMPAIGN_TIME}s"
    # -max_total_time: wall-clock budget
    # -artifact_prefix: where crash artefacts are written
    # -print_final_stats=1: emits a stats block the pipeline greps for
    "$_bin" \
        "$_out/corpus" \
        -max_total_time="$CAMPAIGN_TIME" \
        -artifact_prefix="$_out/crashes/" \
        -print_final_stats=1 \
        >"$_out/run.log" 2>&1 || true
}

run_afl() {
    _bin="$1"
    _name="$2"
    _seed_dir="$3"
    _out="$FINDINGS_DIR/afl/$_name"
    _afl_in="$_out/input"
    _afl_out="$_out/output"
    mkdir -p "$_afl_in" "$_afl_out"

    # AFL requires a non-empty input corpus. Populate from our seed dir
    # without modifying the seed directory itself.
    if [ -d "$_seed_dir" ]; then
        cp -r "$_seed_dir"/. "$_afl_in/" 2>/dev/null || true
    fi
    # Ensure at least one input exists.
    if [ -z "$(ls -A "$_afl_in" 2>/dev/null)" ]; then
        printf '\x00' > "$_afl_in/seed0"
    fi

    echo "[afl] $_name  budget=${CAMPAIGN_TIME}s"
    AFL_SKIP_CPUFREQ=1 \
        afl-fuzz -V "$CAMPAIGN_TIME" \
            -i "$_afl_in" -o "$_afl_out" \
            -- "$_bin" \
        >"$_out/run.log" 2>&1 || true
}

for h in fuzz_packet_parser fuzz_bridge_remap fuzz_suback_client; do
    if [ "$ENGINE" = "libfuzzer" ]; then
        _bin="$BUILD_DIR/${h}_libfuzzer"
        [ -x "$_bin" ] || { echo "[skip] missing $_bin — run build_libfuzzer.sh first" >&2; continue; }
        case "$h" in
            fuzz_packet_parser) run_libfuzzer "$_bin" "$h" "$CORPUS_MQTT" ;;
            fuzz_bridge_remap)  run_libfuzzer "$_bin" "$h" "$CORPUS_MQTT" ;;
            fuzz_suback_client) run_libfuzzer "$_bin" "$h" "$CORPUS_MQTT" ;;
        esac
    else
        _bin="$BUILD_DIR/${h}_afl"
        [ -x "$_bin" ] || { echo "[skip] missing $_bin — run build_afl.sh first" >&2; continue; }
        case "$h" in
            fuzz_packet_parser) run_afl "$_bin" "$h" "$CORPUS_MQTT" ;;
            fuzz_bridge_remap)  run_afl "$_bin" "$h" "$CORPUS_MQTT" ;;
            fuzz_suback_client) run_afl "$_bin" "$h" "$CORPUS_MQTT" ;;
        esac
    fi
done

echo "findings root: $FINDINGS_DIR"
