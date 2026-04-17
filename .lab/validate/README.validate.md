# .lab/validate — Tool Validation Scripts

Individual smoke-tests that confirm each security-analysis tool is installed,
runs correctly against the Mosquitto target, and produces parseable output.
These scripts are **not** the Jenkins pipeline — they are pre-flight checks
to run before integrating a tool into CI.

---

## Purpose

Before a tool is wired into Jenkins, these scripts verify:

1. The binary is on PATH (or at the expected install path).
2. The tool accepts real input and produces structured output.
3. Exit-code semantics are correctly handled (see §Exit-code patterns below).

Each script is standalone. All write artefacts under `validate/results/`.

---

## Prerequisites

The following must be in place before running all validations:

| Requirement | Used by | Notes |
|---|---|---|
| Compiled `build/src/mosquitto` | 02, 03, 07, 08, 09, 10 | Run `cmake` + `make` via `.lab/docker/build_artifact.sh` |
| `SNYK_TOKEN` env var | 06 | Export a valid Snyk API token |
| `EMBA_HOME` env var | 07 | Default `/opt/emba`; set if installed elsewhere |
| `COV_HOME` env var | 03 | Default `/opt/cov-analysis`; set if installed elsewhere |
| Docker daemon | 07 | EMBA requires Docker; on WSL2 start Docker Desktop |
| `core_pattern=core` | 09 | AFL++ warning if not set; fix with `echo core \| sudo tee /proc/sys/kernel/core_pattern` |
| `CODEQL_BIN` env var | 02 | Default `codeql`; set if not on PATH |

---

## Running all validations

```sh
sh .lab/validate/validate_all.sh
```

Or from inside the validate directory:

```sh
cd .lab/validate && sh validate_all.sh
```

The orchestrator runs scripts 01–10 in order. It continues even if a script
fails, then prints a summary table and exits 1 if any script failed.

---

## Running a single validation

```sh
sh .lab/validate/01_validate_secrets.sh
sh .lab/validate/04_validate_sbom_syft.sh
# etc.
```

Some scripts depend on output from earlier ones:

- `05_validate_sca_grype.sh` requires `04_validate_sbom_syft.sh` to have run
  first (reads `results/sbom-cyclonedx.json`).

---

## Results location

All output files are written to:

```
.lab/validate/results/
```

This directory is git-ignored (see `.lab/.gitignore`). Re-running any script
overwrites its previous results.

| File | Produced by |
|---|---|
| `gitleaks_result.json` | 01 |
| `codeql-db/` | 02 |
| `codeql_result.sarif` | 02 |
| `cov-int/` | 03 |
| `coverity_result.json` | 03 |
| `sbom-cyclonedx.json` | 04 |
| `sbom-spdx.json` | 04 |
| `grype_result.json` | 05 |
| `snyk_unmanaged_result.json` | 06 |
| `emba_output/` | 07 |
| `fuzz_packet_parser_validate` | 08 |
| `libfuzzer_validate.log` | 08 |
| `libfuzzer_artifacts/` | 08 |
| `fuzz_packet_parser_afl_validate` | 09 |
| `afl_validate_corpus/` | 09 |
| `afl_validate_findings/` | 09 |
| `afl_validate.log` | 09 |
| `checksec_result.json` | 10 |
| `hardening_check_result.txt` | 10 |
| `readelf_security.txt` | 10 |

---

## SKIP behaviour (Coverity and EMBA)

**Coverity (03)** requires a commercial license and is not installed in most
environments. The script checks for `${COV_HOME}/bin/cov-build`. If Coverity
is not found it prints `SKIP` and exits 0. `validate_all.sh` treats exit 0 as
PASS, so the overall suite does not fail when Coverity is absent.

**EMBA (07)** requires Docker and a manual installation. The script checks for
`${EMBA_HOME}/emba`. If not found it prints `SKIP` and exits 0. Same PASS
treatment in `validate_all.sh`.

To actually run these tools, set the env vars before invoking:

```sh
COV_HOME=/opt/cov-analysis sh .lab/validate/03_validate_sast_coverity.sh
EMBA_HOME=/opt/emba sh .lab/validate/07_validate_sca_emba.sh
```

---

## Exit-code patterns

Several tools exit non-zero to report findings rather than errors. Each script
handles this explicitly:

### `set +e` / `set -e` pattern

Used when a tool's non-zero exit means "findings found, not a tool error":

```sh
set +e
gitleaks detect ...
GITLEAKS_EXIT=$?
set -e
if [ "${GITLEAKS_EXIT}" -gt 1 ]; then
    echo "ERROR: tool error" >&2; exit 1
fi
# exit 0 or 1 both count as PASS
```

Scripts that use this pattern:

| Script | Tool | PASS exit codes |
|---|---|---|
| 01 | Gitleaks | 0 (no secrets), 1 (secrets found) |
| 06 | Snyk | 0 (no vulns), 1 (vulns found) |
| 09 | AFL++ | n/a — uses `\|\| true` + directory check |

### `|| true` pattern

AFL++ (09) is run under `timeout`, which itself exits non-zero when it kills a
process. The script uses `|| true` to suppress the exit code and then checks
for the output directory instead:

```sh
timeout 35 afl-fuzz ... || true
# then:
[ -d "${RESULTS_DIR}/afl_validate_findings" ] || exit 1
```

---

## Fuzzing TU adaptation

Scripts 08 and 09 compile `fuzz_packet_parser.c` with the same Translation
Units (TUs) used by `.lab/fuzzing/build_libfuzzer.sh` and `build_afl.sh`:

```
lib/property_mosq.c  lib/packet_datatypes.c  lib/memory_mosq.c
lib/util_mosq.c      lib/util_topic.c        lib/misc_mosq.c
```

The task spec suggested `src/packet_mosq.c` as a single extra TU, but the
harness calls symbols (`property__read_all`, `mosquitto_property_free_all`,
etc.) that live in the `lib/` TUs above. Using the production build's TU set
keeps validation consistent with the real build.
This deviation is recorded in `.lab/docs/lab-decisions.md`.
