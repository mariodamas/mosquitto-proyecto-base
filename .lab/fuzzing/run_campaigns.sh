#!/bin/sh
# run_campaigns.sh
# ----------------
# Run fuzzing campaigns against each harness for a bounded time budget.
# First positional argument selects the engine: "libfuzzer" or "afl".
# CAMPAIGN_TIME controls the per-harness wall-clock budget in seconds
# (default 1800 = 30 minutes), matching the pipeline's default slice.
#
# Corpus layout:
#   Seed corpus (stable, versioned):
#     .lab/fuzzing/corpus/mqtt/
#     .lab/fuzzing/corpus/cjson/
#   Working corpus (written by libFuzzer, never touches seeds):
#     .lab/fuzzing/findings/libfuzzer/<harness>/corpus/
#   Crashes:
#     .lab/fuzzing/findings/libfuzzer/<harness>/crashes/
#   Metadata:
#     .lab/fuzzing/findings/libfuzzer/<harness>/run.log
#     .lab/fuzzing/findings/libfuzzer/<harness>/exit_code.txt
#     .lab/fuzzing/findings/libfuzzer/<harness>/metadata.txt
#
# Variables:
#   CAMPAIGN_TIME          Per-harness wall-clock budget in seconds (default 1800).
#   ALLOW_FUZZING_FAILURES Set to "true" to allow non-zero harness exit codes
#                          without failing the script. Default: false (strict).

set -eu

HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
BUILD_DIR="${BUILD_DIR:-$HERE/build}"
FINDINGS_DIR="${FINDINGS_DIR:-$HERE/findings}"
CORPUS_MQTT="$HERE/corpus/mqtt"
CORPUS_CJSON="$HERE/corpus/cjson"
CAMPAIGN_TIME="${CAMPAIGN_TIME:-1800}"
ENGINE="${1:-libfuzzer}"
ALLOW_FUZZING_FAILURES="${ALLOW_FUZZING_FAILURES:-false}"

export ASAN_OPTIONS="${ASAN_OPTIONS:-abort_on_error=1:symbolize=1:detect_leaks=0}"
export UBSAN_OPTIONS="${UBSAN_OPTIONS:-print_stacktrace=1:halt_on_error=1}"

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

# _overall_fail tracks whether any harness produced an uncontrolled failure.
_overall_fail=0

run_libfuzzer() {
    _bin="$1"
    _name="$2"
    _seed_dir="$3"
    _out="$FINDINGS_DIR/libfuzzer/$_name"
    mkdir -p "$_out/corpus" "$_out/crashes"

    # Copy seeds into the working corpus. libFuzzer mutates corpus in place;
    # we never pass the seed directory directly to libFuzzer so the versioned
    # seeds remain byte-identical across runs.
    if [ -d "$_seed_dir" ]; then
        cp -r "$_seed_dir"/. "$_out/corpus/" 2>/dev/null || true
    fi

    _start="$(date '+%Y-%m-%dT%H:%M:%S')"

    # Write run header to log before the fuzzer runs, so the log is never
    # empty even if the binary crashes immediately.
    {
        echo "=== libFuzzer run ==="
        echo "binary:        $_bin"
        echo "seed_dir:      $_seed_dir"
        echo "corpus_dir:    $_out/corpus"
        echo "crashes_dir:   $_out/crashes"
        echo "start:         $_start"
        echo "budget:        ${CAMPAIGN_TIME}s"
        echo "ASAN_OPTIONS:  $ASAN_OPTIONS"
        echo "UBSAN_OPTIONS: $UBSAN_OPTIONS"
        echo "=== output ==="
    } > "$_out/run.log"

    echo "[libfuzzer] $_name  budget=${CAMPAIGN_TIME}s"

    _exit_code=0
    set +e
    "$_bin" \
        "$_out/corpus" \
        -max_total_time="$CAMPAIGN_TIME" \
        -artifact_prefix="$_out/crashes/" \
        -print_final_stats=1 \
        >> "$_out/run.log" 2>&1
    _exit_code=$?
    set -e

    _end="$(date '+%Y-%m-%dT%H:%M:%S')"

    echo "$_exit_code" > "$_out/exit_code.txt"

    {
        echo "=== metadata ==="
        echo "harness:        $_name"
        echo "binary:         $_bin"
        echo "seed_dir:       $_seed_dir"
        echo "corpus_dir:     $_out/corpus"
        echo "crashes_dir:    $_out/crashes"
        echo "start:          $_start"
        echo "end:            $_end"
        echo "budget:         ${CAMPAIGN_TIME}s"
        echo "exit_code:      $_exit_code"
        echo "corpus_entries: $(find "$_out/corpus" -maxdepth 1 -type f | wc -l | tr -d ' ')"
        echo "crash_entries:  $(find "$_out/crashes" -maxdepth 1 -type f | wc -l | tr -d ' ')"
    } > "$_out/metadata.txt"

    {
        echo "=== end ==="
        echo "end:       $_end"
        echo "exit_code: $_exit_code"
    } >> "$_out/run.log"

    if [ "$_exit_code" -ne 0 ]; then
        echo "[libfuzzer] WARNING: $_name exited with code $_exit_code" >&2
        _overall_fail=1
    fi
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

    _start="$(date '+%Y-%m-%dT%H:%M:%S')"
    echo "[afl] $_name  budget=${CAMPAIGN_TIME}s"

    _exit_code=0
    set +e
    AFL_SKIP_CPUFREQ=1 \
        afl-fuzz -V "$CAMPAIGN_TIME" \
            -i "$_afl_in" -o "$_afl_out" \
            -- "$_bin" \
        > "$_out/run.log" 2>&1
    _exit_code=$?
    set -e

    _end="$(date '+%Y-%m-%dT%H:%M:%S')"
    echo "$_exit_code" > "$_out/exit_code.txt"

    if [ "$_exit_code" -ne 0 ]; then
        echo "[afl] WARNING: $_name exited with code $_exit_code" >&2
        _overall_fail=1
    fi
}

# Expected harnesses. fuzz_suback_client is excluded because build_libfuzzer.sh
# does not compile it (client-side link closure not yet stubbed). Add it here
# once the build is complete.
LIBFUZZER_HARNESSES="fuzz_packet_parser fuzz_bridge_remap"
AFL_HARNESSES="fuzz_packet_parser fuzz_bridge_remap"

if [ "$ENGINE" = "libfuzzer" ]; then
    for h in $LIBFUZZER_HARNESSES; do
        _bin="$BUILD_DIR/${h}_libfuzzer"
        if [ ! -x "$_bin" ]; then
            echo "[skip] missing $_bin — run build_libfuzzer.sh first" >&2
            continue
        fi
        case "$h" in
            fuzz_packet_parser) run_libfuzzer "$_bin" "$h" "$CORPUS_MQTT" ;;
            fuzz_bridge_remap)  run_libfuzzer "$_bin" "$h" "$CORPUS_MQTT" ;;
        esac
    done
else
    for h in $AFL_HARNESSES; do
        _bin="$BUILD_DIR/${h}_afl"
        if [ ! -x "$_bin" ]; then
            echo "[skip] missing $_bin — run build_afl.sh first" >&2
            continue
        fi
        case "$h" in
            fuzz_packet_parser) run_afl "$_bin" "$h" "$CORPUS_MQTT" ;;
            fuzz_bridge_remap)  run_afl "$_bin" "$h" "$CORPUS_MQTT" ;;
        esac
    done
fi

# ─── Final validation ────────────────────────────────────────────────────────
echo ""
echo "=== Fuzzing campaign summary ==="

_validation_fail=0

if [ "$ENGINE" = "libfuzzer" ]; then
    for h in $LIBFUZZER_HARNESSES; do
        _out="$FINDINGS_DIR/libfuzzer/$h"

        # Only validate harnesses that were actually run.
        if [ ! -d "$_out" ]; then
            continue
        fi

        _log="$_out/run.log"
        _ec_file="$_out/exit_code.txt"
        _corpus_count="$(find "$_out/corpus" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')"
        _crash_count="$(find "$_out/crashes" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')"

        # Read stored exit code.
        if [ -f "$_ec_file" ]; then
            _ec="$(cat "$_ec_file")"
        else
            _ec="missing"
        fi

        # Validate log exists and is non-empty.
        if [ ! -f "$_log" ]; then
            echo "[FAIL] $h: run.log missing" >&2
            _validation_fail=1
        elif [ ! -s "$_log" ]; then
            echo "[FAIL] $h: run.log is empty" >&2
            _validation_fail=1
        else
            _log_size="$(wc -c < "$_log" | tr -d ' ')"
            echo "[OK]   $h  exit_code=$_ec  log_bytes=$_log_size  corpus=$_corpus_count  crashes=$_crash_count"
        fi

        # Validate exit_code.txt exists.
        if [ ! -f "$_ec_file" ]; then
            echo "[FAIL] $h: exit_code.txt missing" >&2
            _validation_fail=1
        fi

        # Validate corpus has at least one entry.
        if [ "$_corpus_count" -eq 0 ] 2>/dev/null; then
            echo "[FAIL] $h: working corpus is empty" >&2
            _validation_fail=1
        fi

        # If exit code is non-zero and strict mode, record failure.
        if [ -f "$_ec_file" ] && [ "$_ec" != "0" ]; then
            if [ "$ALLOW_FUZZING_FAILURES" != "true" ]; then
                echo "[FAIL] $h: exit_code=$_ec (set ALLOW_FUZZING_FAILURES=true to suppress)" >&2
                _validation_fail=1
            fi
        fi
    done
fi

echo "findings root: $FINDINGS_DIR"

if [ "$_validation_fail" -ne 0 ]; then
    echo "[ERROR] One or more harnesses failed validation." >&2
    exit 1
fi

if [ "$_overall_fail" -ne 0 ] && [ "$ALLOW_FUZZING_FAILURES" != "true" ]; then
    echo "[ERROR] One or more harnesses exited non-zero. Set ALLOW_FUZZING_FAILURES=true to allow." >&2
    exit 1
fi

exit 0
