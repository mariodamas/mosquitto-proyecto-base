# Fuzzing — Eclipse Mosquitto v2.0.18 (lab branch)

This directory holds the harnesses, corpus, and helper scripts used by the
Jenkins DevSecOps pipeline for coverage-guided fuzzing of Mosquitto.

**Scope.** These scripts prepare and run campaigns. They do **not** install
compilers, fuzzers, or sanitizer runtimes. The analysis host is expected to
provide `clang`, `afl-clang-fast`, `llvm-profdata`, and `llvm-cov` on the
PATH. Jenkins orchestration lives elsewhere; nothing here calls Jenkins.

## Layout

| Path                                      | Role                                                 |
| ----------------------------------------- | ---------------------------------------------------- |
| `harnesses/fuzz_packet_parser.c`          | Broker-side MQTT 5 property / packet parser harness. |
| `harnesses/fuzz_bridge_remap.c`           | Broker-side bridge inbound-topic remap harness.      |
| `harnesses/fuzz_suback_client.c`          | libmosquitto client-side SUBACK parser harness.      |
| `corpus/mqtt/*.bin`                       | Minimal valid MQTT 3.1.1 seeds (generated).          |
| `corpus/cjson/*.json`                     | JSON seeds for property-string decoding (generated). |
| `corpus/generate_corpus.py`               | Regenerates all seeds; source of truth.              |
| `build_libfuzzer.sh`                      | Builds all harnesses with libFuzzer + ASan + UBSan.  |
| `build_afl.sh`                            | Builds all harnesses with `afl-clang-fast` + ASan.   |
| `run_campaigns.sh`                        | Runs libFuzzer or AFL++ campaigns with bounded time. |
| `measure_coverage.sh`                     | Builds instrumented binaries, runs corpora, emits LLVM coverage reports. |
| `build/`                                  | Output of build scripts (git-ignored).               |
| `findings/libfuzzer/` `findings/afl/`     | Campaign logs, crashes, corpora (git-ignored).       |
| `coverage/`                               | `.profraw`, `.profdata`, HTML coverage (git-ignored).|

## Corpus separation

The fuzzing setup distinguishes three categories of corpus data:

| Category | Location | Description |
|----------|----------|-------------|
| **Seed corpus** (stable) | `corpus/mqtt/`, `corpus/cjson/` | Minimal valid inputs generated deterministically by `generate_corpus.py`. Versioned in the repository. Only 3 MQTT seeds and 6 JSON seeds. Never written to by libFuzzer. |
| **Working corpus** (evolved) | `findings/libfuzzer/<harness>/corpus/` | Seeds copied from the stable corpus at campaign start; libFuzzer mutates and expands these. Saved as build artefact but **not committed** back to `corpus/`. |
| **Crashes / findings** | `findings/libfuzzer/<harness>/crashes/` | Inputs that triggered crashes or sanitizer violations. Saved as artefacts for triage. |
| **Run metadata** | `findings/libfuzzer/<harness>/run.log`, `exit_code.txt`, `metadata.txt` | Execution record: binary, seed dir, corpus dir, timestamps, exit code, corpus size. |

### Promoting evolved corpus entries

Entries in `findings/libfuzzer/<harness>/corpus/` that improve coverage may be
promoted to the seed corpus, but only after **manual review**:

1. Inspect the candidate input (e.g. `xxd <file>`).
2. Confirm it exercises a new parser path and is not a crash input.
3. Copy it to `corpus/mqtt/` or `corpus/cjson/` with a descriptive name.
4. Re-run `python3 corpus/generate_corpus.py` — this **will** delete the directory
   and regenerate only the canonical seeds, so copy the file **before** running it.

> **Never** automatically commit the contents of `findings/` to `corpus/`.
> libFuzzer-generated entries are build artefacts, not source files.

## Environment

| Variable                  | Default              | Meaning                                           |
| ------------------------- | -------------------- | ------------------------------------------------- |
| `MOSQUITTO_SRC`           | `../../`             | Path to the Mosquitto source tree.                |
| `CAMPAIGN_TIME`           | `1800` (seconds)     | Per-harness wall-clock budget for `run_campaigns.sh`. |
| `ALLOW_FUZZING_FAILURES`  | `false`              | If `true`, `run_campaigns.sh` exits 0 even when a harness exits non-zero. Use in CI for informational campaigns. |
| `AFL_USE_ASAN`            | `1` (set by script)  | AFL++ + AddressSanitizer.                         |
| `AFL_USE_UBSAN`           | `1` (set by script)  | AFL++ + UndefinedBehaviorSanitizer.               |

## Typical pipeline usage

```sh
# 1. regenerate corpus
python3 corpus/generate_corpus.py

# 2. build both flavours
./build_libfuzzer.sh
./build_afl.sh

# 3. run campaigns (set CAMPAIGN_TIME explicitly in CI)
CAMPAIGN_TIME=1800 ./run_campaigns.sh libfuzzer
CAMPAIGN_TIME=1800 ./run_campaigns.sh afl

# 4. coverage
./measure_coverage.sh
```

## Host prerequisites for AFL++

AFL++ refuses to run while `/proc/sys/kernel/core_pattern` starts with `|`
(the systemd-coredump piping pattern on most modern Linux hosts). The
analysis host must either:

- Set `echo core | sudo tee /proc/sys/kernel/core_pattern` before a campaign,
  or
- Export `AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1` (only acceptable for
  informational runs — crashes may be missed).

`run_campaigns.sh` prints a reminder; it does not modify `core_pattern`
because doing so requires root and has host-wide side effects.

## Source-tree dependency

All three harnesses include Mosquitto private headers directly (see
`.lab/docs/lab-decisions.md`). They compile against the upstream source tree
without any patch. The build scripts assume the tree layout produced by
`git checkout v2.0.18`.
