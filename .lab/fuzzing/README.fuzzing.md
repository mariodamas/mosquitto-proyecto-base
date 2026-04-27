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
| `harnesses/fuzz_suback_client.c`          | libmosquitto client-side SUBACK parser (not yet enabled — see build_libfuzzer.sh). |
| `corpus/mqtt/*.bin`                       | Minimal valid MQTT 3.1.1 seeds (generated, versioned). |
| `corpus/cjson/*.json`                     | JSON seeds for property-string decoding (generated, versioned). |
| `corpus/generate_corpus.py`               | Regenerates all seeds; cleans corpus dirs first.     |
| `build_libfuzzer.sh`                      | Builds the **enabled** harnesses with libFuzzer + ASan + UBSan (currently `fuzz_packet_parser` and `fuzz_bridge_remap`). |
| `build_afl.sh`                            | Builds the enabled harnesses with `afl-clang-fast` + ASan. |
| `run_campaigns.sh`                        | Runs libFuzzer or AFL++ campaigns with bounded time. |
| `measure_coverage.sh`                     | Builds instrumented binaries, runs corpora, emits LLVM coverage reports. |
| `build/`                                  | Output of build scripts (git-ignored).               |
| `findings/libfuzzer/` `findings/afl/`     | Campaign logs, crashes, corpora (git-ignored).       |
| `coverage/`                               | `.profraw`, `.profdata`, HTML coverage (git-ignored).|

## Corpus model

The fuzzing setup manages five distinct corpus categories:

| Category | Location | Versioned? | Written by libFuzzer? | Description |
|----------|----------|:----------:|:---------------------:|-------------|
| **Seed corpus** | `corpus/mqtt/`, `corpus/cjson/` | ✅ yes | ❌ no | Minimal valid inputs generated deterministically by `generate_corpus.py`. Small, stable, and reviewed. Regenerated from scratch on every `generate_corpus.py` run. |
| **Working corpus** | `findings/libfuzzer/<harness>/corpus/` | ❌ no | ✅ yes | Seeds copied from the stable corpus (and merged from the persistent corpus) at campaign start. libFuzzer mutates and extends this dir in place. Saved as a build artefact. |
| **Crash corpus** | `findings/libfuzzer/<harness>/crashes/` | ❌ no | ✅ yes | Inputs that triggered crashes or sanitizer violations. Each file requires manual triage. Never merged into working or persistent corpus. |
| **Persistent corpus** | `$FUZZING_PERSISTENT_CORPUS_DIR/<harness>/` (outside the repo) | — | via sync | Long-lived corpus on a host-mounted volume (e.g. `/opt/devsecops-lab/fuzzing-corpus/mosquitto`). Merged into the working corpus before each run. Updated conservatively (`cp -n`) after each successful run. Survives across builds without touching the repo. |
| **Regression corpus** | promoted manually into `corpus/` | ✅ yes | ❌ no | Entries from the working or persistent corpus that have been inspected, found to improve coverage meaningfully, and copied to the seed corpus with a descriptive name. Requires explicit human review. |

### Seed corpus — lifecycle

`generate_corpus.py` is the **sole authority** for what lives in `corpus/mqtt/`
and `corpus/cjson/`. Every run of the script:

1. Deletes and recreates those two directories.
2. Writes exactly 3 MQTT 3.1.1 binary seeds and 6 JSON seeds.
3. Prints a summary: `[OK] MQTT seeds: 3`, `[OK] cJSON seeds: 6`.

Because the output is deterministic, `git status` remains clean after
re-running the script on an unmodified repo.

### Working corpus — lifecycle

Each campaign run:
1. Creates a fresh `findings/libfuzzer/<harness>/corpus/` directory.
2. Copies seeds from `corpus/mqtt/` (or `corpus/cjson/`).
3. If `FUZZING_PERSISTENT_CORPUS_DIR` is set, merges entries from the
   persistent dir (`cp -n` — no overwrites).
4. Runs libFuzzer, which mutates and grows this directory.
5. Saves the final directory as a build artefact.

The seed corpus in `corpus/` is **never passed directly** to libFuzzer and is
**never written to** by the campaign runner.

### Persistent corpus — lifecycle

The persistent corpus lives on a volume mounted into the Docker container in CI
(e.g. `/opt/devsecops-lab/fuzzing-corpus/mosquitto/<harness>/`).

Before the run: entries are merged (`cp -n`) into the working corpus.  
After the run: new entries from the working corpus are synced back (`cp -n`).

Because `cp -n` never overwrites existing entries, the persistent corpus only
grows; crashes and regressions cannot destroy previously discovered coverage.

Crashes are **never** synced to the persistent corpus.

### Promoting entries to the seed corpus

Entries in the working or persistent corpus that improve coverage may be
promoted to the seed corpus, but only after **manual review**:

1. Inspect the candidate (`xxd <file>` or a hex viewer).
2. Confirm it exercises a new parser path and is not a crash input.
3. Give it a descriptive name (e.g. `connect_will_qos1.bin`).
4. Copy it to `corpus/mqtt/` **before** running `generate_corpus.py`.

> `generate_corpus.py` deletes and recreates the seed dirs — copy first.

> **Never** automatically commit the contents of `findings/` or the persistent
> corpus to `corpus/`. libFuzzer-generated entries are build artefacts.

## Environment

| Variable                        | Default    | Meaning |
| ------------------------------- | ---------- | ------- |
| `MOSQUITTO_SRC`                 | `../../`   | Path to the Mosquitto source tree. |
| `CAMPAIGN_TIME`                 | `1800` s   | Per-harness wall-clock budget for `run_campaigns.sh`. |
| `ALLOW_FUZZING_FAILURES`        | _(unset)_  | Set to `true` to allow non-zero harness exit codes without failing the script. Infrastructure errors (empty log, missing artefacts, empty corpus) always fail regardless. |
| `FUZZING_PERSISTENT_CORPUS_DIR` | _(unset)_  | Base directory for the persistent corpus (one subdirectory per harness). If unset, no persistent corpus is used. |
| `AFL_USE_ASAN`                  | `1`        | AFL++ + AddressSanitizer (set by build script). |
| `AFL_USE_UBSAN`                 | `1`        | AFL++ + UndefinedBehaviorSanitizer (set by build script). |

## Typical pipeline usage

```sh
# 1. Regenerate seed corpus (cleans corpus dirs first)
python3 corpus/generate_corpus.py

# 2. Build enabled harnesses
./build_libfuzzer.sh   # fuzz_packet_parser, fuzz_bridge_remap
./build_afl.sh

# 3. Run campaigns (set CAMPAIGN_TIME explicitly in CI)
CAMPAIGN_TIME=1800 ./run_campaigns.sh libfuzzer
CAMPAIGN_TIME=1800 ./run_campaigns.sh afl

# 4. Run with persistent corpus (CI with mounted volume)
FUZZING_PERSISTENT_CORPUS_DIR=/opt/devsecops-lab/fuzzing-corpus/mosquitto \
ALLOW_FUZZING_FAILURES=true \
CAMPAIGN_TIME=60 \
./run_campaigns.sh libfuzzer

# 5. Coverage report
./measure_coverage.sh
```

## Artefacts written per harness

After a campaign, each `findings/libfuzzer/<harness>/` contains:

| File / Dir    | Content |
|---------------|---------|
| `run.log`     | Full execution log: header with run parameters, libFuzzer output, footer with exit code and corpus counts. Never empty if the harness binary was launched. |
| `exit_code.txt` | Single integer: the exit code of the libFuzzer process. |
| `metadata.txt`  | Key-value summary: harness, binary, seed/corpus/crash dirs, timestamps, counts, persistent sync status. |
| `corpus/`     | Working corpus after the campaign. |
| `crashes/`    | Crash and sanitizer-violation inputs (if any). |

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

The enabled harnesses (`fuzz_packet_parser`, `fuzz_bridge_remap`) include
Mosquitto private headers directly (see `.lab/docs/lab-decisions.md`). They
compile against the upstream source tree without any patch. The build scripts
assume the tree layout produced by `git checkout v2.0.18`.

`fuzz_suback_client` sources a client-side object graph that is not yet
stubbed; it is excluded from `build_libfuzzer.sh` until the link closure is
resolved.
