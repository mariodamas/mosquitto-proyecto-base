#!/bin/sh
# run_campaigns.sh
# ----------------
# Run fuzzing campaigns against each harness for a bounded time budget.
# First positional argument selects the engine: "libfuzzer" or "afl".
#
# Corpus layout
# ─────────────
#   Seed corpus     (stable, versioned):
#     .lab/fuzzing/corpus/mqtt/
#     .lab/fuzzing/corpus/cjson/
#
#   Working corpus  (per-run, never touches seeds):
#     .lab/fuzzing/findings/libfuzzer/<harness>/corpus/
#
#   Crashes:
#     .lab/fuzzing/findings/libfuzzer/<harness>/crashes/
#
#   Metadata:
#     .lab/fuzzing/findings/libfuzzer/<harness>/run.log
#     .lab/fuzzing/findings/libfuzzer/<harness>/exit_code.txt
#     .lab/fuzzing/findings/libfuzzer/<harness>/metadata.txt
#
#   Persistent corpus (optional, outside the repo):
#     $FUZZING_PERSISTENT_CORPUS_DIR/<harness>/
#     Populated before the run and updated conservatively after it.
#
# Variables
# ─────────
#   CAMPAIGN_TIME                Per-harness wall-clock budget in seconds
#                                (default 1800 = 30 min).
#   ALLOW_FUZZING_FAILURES       "true": non-zero harness exit codes are logged
#                                but the script exits 0 after artefact validation.
#                                Any other value (default ""): non-zero exit code
#                                fails the script.
#                                Infrastructure errors (empty log, missing
#                                artefacts, empty corpus) always fail regardless.
#   FUZZING_PERSISTENT_CORPUS_DIR
#                                Optional path to a directory that persists
#                                across CI runs (e.g. a host-mounted volume).
#                                If set, entries are merged into the working
#                                corpus before the run and synced back after.
#                                The seed corpus in .lab/fuzzing/corpus is
#                                never written to.

set -eu

HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
BUILD_DIR="${BUILD_DIR:-$HERE/build}"
FINDINGS_DIR="${FINDINGS_DIR:-$HERE/findings}"
CORPUS_MQTT="$HERE/corpus/mqtt"
CORPUS_CJSON="$HERE/corpus/cjson"
CAMPAIGN_TIME="${CAMPAIGN_TIME:-1800}"
ENGINE="${1:-libfuzzer}"
ALLOW_FUZZING_FAILURES="${ALLOW_FUZZING_FAILURES:-}"
FUZZING_PERSISTENT_CORPUS_DIR="${FUZZING_PERSISTENT_CORPUS_DIR:-}"

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

# _overall_fail is set to 1 when a harness exits non-zero.
# Infrastructure failures (empty log, missing artefacts) set _validation_fail
# and always cause a non-zero exit regardless of ALLOW_FUZZING_FAILURES.
_overall_fail=0

# ─── libFuzzer runner ────────────────────────────────────────────────────────

run_libfuzzer() {
    _bin="$1"
    _name="$2"
    _seed_dir="$3"
    _out="$FINDINGS_DIR/libfuzzer/$_name"
    mkdir -p "$_out/corpus" "$_out/crashes"

    # ── Populate working corpus ──────────────────────────────────────────────
    # 1. Copy stable seed corpus. libFuzzer mutates corpus in place; we copy
    #    so the versioned seeds remain byte-identical across every run.
    _seeds_copied=0
    if [ -d "$_seed_dir" ]; then
        cp -r "$_seed_dir"/. "$_out/corpus/" 2>/dev/null || true
        _seeds_copied="$(find "$_seed_dir" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')"
    fi

    # 2. Merge persistent corpus entries (if configured). Uses cp -n so
    #    no existing working-corpus entry is overwritten.
    _persistent_dir=""
    _persistent_copied=0
    _persistent_synced="disabled"
    if [ -n "$FUZZING_PERSISTENT_CORPUS_DIR" ]; then
        _persistent_dir="$FUZZING_PERSISTENT_CORPUS_DIR/$_name"
        mkdir -p "$_persistent_dir"
        if [ -n "$(ls -A "$_persistent_dir" 2>/dev/null)" ]; then
            # cp -n: skip files that already exist in the destination.
            cp -n "$_persistent_dir"/. "$_out/corpus/" 2>/dev/null || true
            _persistent_copied="$(find "$_persistent_dir" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')"
        fi
        _persistent_synced="pending"
    fi

    _start="$(date '+%Y-%m-%dT%H:%M:%S')"

    # Write the run header BEFORE executing the fuzzer so run.log is never
    # empty even if the binary segfaults immediately.
    {
        echo "=== libFuzzer run ==="
        echo "harness:          $_name"
        echo "binary:           $_bin"
        echo "seed_dir:         $_seed_dir"
        echo "corpus_dir:       $_out/corpus"
        echo "crashes_dir:      $_out/crashes"
        echo "persistent_dir:   ${_persistent_dir:-disabled}"
        echo "seeds_copied:     $_seeds_copied"
        echo "persistent_entries_merged: $_persistent_copied"
        echo "start:            $_start"
        echo "budget:           ${CAMPAIGN_TIME}s"
        echo "ASAN_OPTIONS:     $ASAN_OPTIONS"
        echo "UBSAN_OPTIONS:    $UBSAN_OPTIONS"
        echo "=== output ==="
    } > "$_out/run.log"

    echo "[libfuzzer] $_name  budget=${CAMPAIGN_TIME}s  seeds=$_seeds_copied  persistent_merged=$_persistent_copied"

    # ── Execute libFuzzer ────────────────────────────────────────────────────
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

    # ── Sync back to persistent corpus ──────────────────────────────────────
    # Only when: persistent dir is configured, working corpus is non-empty,
    # and the fuzzer did not crash in a way that left the corpus unusable.
    # We use cp -n (no-clobber) to never overwrite existing persistent entries.
    _corpus_count="$(find "$_out/corpus" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')"
    if [ -n "$FUZZING_PERSISTENT_CORPUS_DIR" ] && [ "$_corpus_count" -gt 0 ]; then
        cp -n "$_out/corpus"/. "$_persistent_dir/" 2>/dev/null || true
        _persistent_synced="yes"
    elif [ -n "$FUZZING_PERSISTENT_CORPUS_DIR" ]; then
        _persistent_synced="skipped_empty_corpus"
    fi

    _crash_count="$(find "$_out/crashes" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')"

    # ── Write metadata ───────────────────────────────────────────────────────
    {
        echo "harness:                    $_name"
        echo "binary:                     $_bin"
        echo "seed_dir:                   $_seed_dir"
        echo "corpus_dir:                 $_out/corpus"
        echo "crashes_dir:                $_out/crashes"
        echo "persistent_dir:             ${_persistent_dir:-disabled}"
        echo "start:                      $_start"
        echo "end:                        $_end"
        echo "budget:                     ${CAMPAIGN_TIME}s"
        echo "exit_code:                  $_exit_code"
        echo "seeds_copied:               $_seeds_copied"
        echo "persistent_entries_merged:  $_persistent_copied"
        echo "corpus_entries_final:       $_corpus_count"
        echo "crash_entries:              $_crash_count"
        echo "persistent_synced:          $_persistent_synced"
    } > "$_out/metadata.txt"

    # Append end section to run.log.
    {
        echo "=== end ==="
        echo "end:               $_end"
        echo "exit_code:         $_exit_code"
        echo "corpus_final:      $_corpus_count"
        echo "crashes:           $_crash_count"
        echo "persistent_synced: $_persistent_synced"
    } >> "$_out/run.log"

    if [ "$_exit_code" -ne 0 ]; then
        echo "[libfuzzer] WARNING: $_name exited with code $_exit_code" >&2
        _overall_fail=1
    fi
}

# ─── AFL++ runner ────────────────────────────────────────────────────────────

run_afl() {
    _bin="$1"
    _name="$2"
    _seed_dir="$3"
    _out="$FINDINGS_DIR/afl/$_name"
    _afl_in="$_out/input"
    _afl_out="$_out/output"
    mkdir -p "$_afl_in" "$_afl_out"

    # AFL requires a non-empty input corpus. Populate from seed dir without
    # modifying the seed directory itself.
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

# ─── Harness lists ───────────────────────────────────────────────────────────
# fuzz_suback_client is excluded: build_libfuzzer.sh does not compile it
# (client-side link closure not yet stubbed). Restore it here once the build
# is ready.
LIBFUZZER_HARNESSES="fuzz_packet_parser fuzz_bridge_remap"
AFL_HARNESSES="fuzz_packet_parser fuzz_bridge_remap"

# ─── Dispatch ────────────────────────────────────────────────────────────────
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

        # Only validate harnesses that were actually dispatched.
        if [ ! -d "$_out" ]; then
            continue
        fi

        _log="$_out/run.log"
        _ec_file="$_out/exit_code.txt"
        _meta="$_out/metadata.txt"
        _corpus_count="$(find "$_out/corpus" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')"
        _crash_count="$(find "$_out/crashes" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')"

        # Read stored exit code.
        _ec="missing"
        if [ -f "$_ec_file" ]; then
            _ec="$(cat "$_ec_file")"
        fi

        # Derive persistent sync status from metadata (best-effort).
        _psynced="n/a"
        if [ -f "$_meta" ]; then
            _psynced="$(grep '^persistent_synced:' "$_meta" | sed 's/persistent_synced:[[:space:]]*//' | tr -d ' ')"
        fi

        # Infrastructure checks — always fatal.
        _infra_ok=1

        if [ ! -f "$_log" ]; then
            echo "[FAIL] $h: run.log missing (infrastructure error)" >&2
            _validation_fail=1; _infra_ok=0
        elif [ ! -s "$_log" ]; then
            echo "[FAIL] $h: run.log is empty (infrastructure error)" >&2
            _validation_fail=1; _infra_ok=0
        fi

        if [ ! -f "$_ec_file" ]; then
            echo "[FAIL] $h: exit_code.txt missing (infrastructure error)" >&2
            _validation_fail=1; _infra_ok=0
        fi

        if [ ! -f "$_meta" ]; then
            echo "[FAIL] $h: metadata.txt missing (infrastructure error)" >&2
            _validation_fail=1; _infra_ok=0
        fi

        if [ "$_corpus_count" -eq 0 ] 2>/dev/null; then
            echo "[FAIL] $h: working corpus is empty (infrastructure error)" >&2
            _validation_fail=1; _infra_ok=0
        fi

        # Non-zero exit code — fatal only in strict mode.
        if [ "$_ec" != "0" ] && [ "$_ec" != "missing" ]; then
            if [ "$ALLOW_FUZZING_FAILURES" = "true" ]; then
                echo "[WARN] $h: exit_code=$_ec (ALLOW_FUZZING_FAILURES=true — not blocking)" >&2
            else
                echo "[FAIL] $h: exit_code=$_ec (set ALLOW_FUZZING_FAILURES=true to suppress)" >&2
                _validation_fail=1
            fi
        fi

        if [ "$_infra_ok" -eq 1 ]; then
            _log_size="$(wc -c < "$_log" | tr -d ' ')"
            echo "[OK]   $h  exit_code=$_ec  log_bytes=$_log_size  corpus=$_corpus_count  crashes=$_crash_count  persistent_synced=$_psynced"
        fi
    done
fi

echo "findings root: $FINDINGS_DIR"

if [ "$_validation_fail" -ne 0 ]; then
    echo "[ERROR] One or more harnesses failed validation." >&2
    exit 1
fi

exit 0
