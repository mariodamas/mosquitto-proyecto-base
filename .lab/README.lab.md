# Lab Branch — Eclipse Mosquitto v2.0.18

This directory exists **only** on the `exp/mosquitto-v2.0.18-lab` branch.
It is ignored by, and not present on, `exp/mosquitto-v2.0.18-upstream`.

## Purpose

The lab branch is the **target of analysis** for a Jenkins DevSecOps pipeline
focused on embedded C/C++ security tooling. It carries controlled, synthetic
material that the pipeline is expected to discover — secrets, a vendored
vulnerable dependency, fuzz harnesses, reproducible-build tooling — on top of
an unmodified Mosquitto `v2.0.18` tree.

## Two-branch model

| Branch                             | Purpose                                                           |
| ---------------------------------- | ----------------------------------------------------------------- |
| `exp/mosquitto-v2.0.18-upstream`   | Pristine upstream tag. Establishes *ecological validity*: numbers |
|                                    | produced against it reflect a real OSS project.                    |
| `exp/mosquitto-v2.0.18-lab`        | Same tree + `.lab/` + `CMakeLists.lab.txt`. Gives the pipeline    |
|                                    | known-present signals so detection/miss behaviour is measurable.   |

The lab branch must not modify any upstream file. Any check that diffs the
two branches should see only `.lab/**` and `CMakeLists.lab.txt`.

## Why Mosquitto v2.0.18

- Released mid-2023; widely deployed in IoT / edge / embedded contexts, matching
  the target domain of the pipeline.
- Sits between newer CVE disclosures (CVE-2024-8376, CVE-2024-3935,
  CVE-2024-10525 affect later 2.x lines but the same code paths are present or
  closely adjacent here) and older tagged releases, so the broker-side packet
  pipeline, the bridge remap path, and the client-side SUBACK handler are all
  analysable without backporting.
- Tag is stable and reproducible; no release-candidate churn.

## What `.lab/` contains

| Path                                        | Role in the pipeline                                                    |
| ------------------------------------------- | ----------------------------------------------------------------------- |
| `.lab/secrets/`                             | Synthetic but realistic secrets — detection target for Gitleaks.        |
| `.lab/vendor/cjson-1.7.14/`                 | Unmanaged vendored dependency — detection target for SCA / SBOM tools.  |
| `.lab/fuzzing/harnesses/`                   | libFuzzer-shaped harnesses for three specific CVE-class bug surfaces.   |
| `.lab/fuzzing/corpus/`                      | Seed corpora (binary MQTT frames + JSON samples) for fuzzing campaigns. |
| `.lab/fuzzing/*.sh`                         | Build / run / coverage helpers, tool-agnostic.                          |
| `.lab/docker/`                              | Reproducible build of a Mosquitto ELF for later binary analysis.        |
| `.lab/docs/lab-decisions.md`                | Technical decision log (this branch's "why" file).                      |
| `CMakeLists.lab.txt` (repo root)            | Additive build description for the vendored cJSON target.               |

## What is intentionally synthetic

Everything under `.lab/secrets/` is **synthetic**:
- AWS-style keys, GitHub PAT, JWT-like tokens, an RSA block and hardcoded
  passwords are fabricated strings that match the *shape* of real credentials.
- They follow the format expected by secret-scanner regexes so that a miss is
  a real miss, not an artefact of unrealistic test data.
- None of these credentials are valid against any real system.

The vendored `cJSON 1.7.14` is a real copy of upstream code at that version —
it is vendored deliberately because that version has known advisories. It is
not a placeholder or a simplified stub.

## What the pipeline is expected to analyse

| Phase            | Signal on lab branch                                                                 |
| ---------------- | ------------------------------------------------------------------------------------ |
| Secrets          | `.lab/secrets/*` — Gitleaks / detect-secrets should flag the synthetic material.      |
| SAST             | Upstream C tree + `.lab/vendor/` — flawfinder / semgrep / cppcheck / CodeQL surface.  |
| SBOM / SCA       | The vendored cJSON directory — SBOM tools should list it; SCA should flag its CVEs.   |
| Vendoring        | Presence of `.lab/vendor/cjson-1.7.14/` as unmanaged third-party code.                |
| Binary analysis  | Artefact produced by `.lab/docker/build_artifact.sh` — checksec / hardening checks.   |
| Sanitizers       | libFuzzer/AFL builds produced under `.lab/fuzzing/build/` via ASan+UBSan.             |
| Fuzzing          | Three harnesses, CVE-adjacent surfaces, reproducible campaigns.                       |
| Hardening        | Flags baked into `Dockerfile.build` reflected in the ELF produced in `docker/output/`. |

Scripts here never install tooling and never call Jenkins. They assume the
analysis host already has the relevant toolchain available.
