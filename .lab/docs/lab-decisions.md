# Lab branch — technical decision log

This file records concrete decisions made while preparing
`exp/mosquitto-v2.0.18-lab`. It is the single source of truth for any
deviation from the requested plan.

## Target selection

### Why Eclipse Mosquitto v2.0.18

- v2.0.18 is a stable tagged release on the 2.0 LTS line. No release-candidate
  churn, reproducible across hosts.
- Three CVE-class bug surfaces we want to exercise are all present (or have a
  very close structural equivalent) in v2.0.18:
  - CVE-2024-8376 — broker-side MQTT 5 property / packet processing path
    exercised via `lib/property_mosq.c::property__read_all` and the broker
    handlers under `src/handle_*.c`.
  - CVE-2024-3935 — bridge inbound topic remap (`src/bridge_topic.c::bridge__remap_topic_in`).
  - CVE-2024-10525 — client-side SUBACK handling
    (`lib/handle_suback.c::handle__suback`).
- The release is widely deployed in IoT / edge systems, matching the embedded
  C/C++ focus of the DevSecOps pipeline.

### Why an upstream/lab split rather than a single branch

The two branches serve different research purposes and must not contaminate
each other:

- `exp/mosquitto-v2.0.18-upstream` is the ecological-validity baseline. Numbers
  produced against it (SAST findings, SBOM contents, fuzzing coverage) reflect
  a real unmodified OSS project. That requires zero lab additions.
- `exp/mosquitto-v2.0.18-lab` carries known-present signals so that the
  pipeline's detection / miss behaviour is measurable under controlled
  conditions.

Diffing the two branches must only show `.lab/**` and `CMakeLists.lab.txt`.
This is enforced by keeping all additions under `.lab/` (plus the one
top-level additive CMake file).

### Why only `.lab/` and `CMakeLists.lab.txt` are added

- `.lab/` is an unambiguous containment boundary. Pipeline rules can include
  or exclude lab material with a single path prefix.
- `CMakeLists.lab.txt` is additive: it is not included by the upstream build
  unless a lab step invokes it explicitly. No upstream `CMakeLists.txt` is
  touched, so the ecological-validity branch remains bit-identical to the tag.

## Vendored dependency

### Why cJSON 1.7.14

- Vendoring (rather than a package-manager dependency) is the point: it exercises
  the SBOM / SCA detection path for *unmanaged* third-party code, which is a
  common real-world weakness in embedded C/C++ projects.
- 1.7.14 is a version with known advisories and is widely cited in SCA
  databases; a competent SCA tool should identify it by the contents of
  `cJSON.c` / `cJSON.h` alone, without needing a manifest.
- The files are verbatim upstream source from
  `https://github.com/DaveGamble/cJSON` at tag `v1.7.14`. They are not
  synthetic stubs.

### Why not a newer cJSON

A newer cJSON (1.7.18+) would defeat the purpose: SCA tools would produce
zero findings, so detection vs. miss behaviour would be indistinguishable from
"tool broken".

## Fuzzing

### Why these three CVE targets

- CVE-2024-8376 (`fuzz_packet_parser.c`) — broker-side stateful packet
  processing. Highest-value attack surface: network-reachable, pre-auth.
- CVE-2024-3935 (`fuzz_bridge_remap.c`) — bridge topic remapping memory
  corruption. Tests the inbound topic-rewrite path when the broker peers with
  another broker; this is authenticated but attacker-controlled in bridge
  topology.
- CVE-2024-10525 (`fuzz_suback_client.c`) — client-side SUBACK handling.
  Included *specifically* because it is not broker-centric; it exercises the
  libmosquitto client library. This matters because a full SDLC pipeline must
  also assess shipped client artefacts, not only the broker binary.

### Source-tree adaptations for harnesses

None of the three target functions are exposed via public API headers, so the
harnesses include the private headers directly:

- `fuzz_packet_parser.c` uses `lib/mosquitto_internal.h`, `lib/packet_mosq.h`,
  `lib/property_mosq.h`. The property-parsing path is invoked through
  `property__read_all`, which is the real parsing entry reached from the
  broker's packet handlers.
- `fuzz_bridge_remap.c` calls `bridge__remap_topic_in` from
  `src/bridge_topic.c`. The broker binary defines this as a non-static
  function (`int bridge__remap_topic_in(struct mosquitto *context, char **topic)`),
  so the harness links `src/bridge_topic.c` directly.
- `fuzz_suback_client.c` calls `handle__suback` from `lib/handle_suback.c`
  after populating `mosq->in_packet` with fuzz bytes and setting
  `command = CMD_SUBACK`.

These choices were made to keep harnesses realistic without patching any
upstream file. The harness TU must be compiled with the same include paths
used by the upstream build (`lib/`, `src/`, `include/`).

### Why POSIX `sh` for build/run/coverage scripts

All fuzzing helpers default to `#!/bin/sh` with `set -eu`. This keeps them
portable across Alpine-based and minimal Debian-based analysis containers.

`build_libfuzzer.sh` and `build_afl.sh` remain `#!/bin/sh`. No bash-only
construct was required during implementation, so the documented exception
(switching to `#!/bin/bash`) was **not** used.

### What could not be fully verified in this session

- `clang --syntax-only` on the three harnesses was not executed in this
  session because clang is not installed on the Windows host where the
  repository was prepared. The intended invocation is documented in
  `.lab/fuzzing/README.fuzzing.md` and reproducibly runs on the analysis host.
- `build_libfuzzer.sh` / `build_afl.sh` / `run_campaigns.sh` /
  `measure_coverage.sh` were syntax-checked with `sh -n` (see verification
  summary), not executed end-to-end. Actual compilation belongs to the pipeline
  step, not to this repository preparation step.
- The reproducible-build Dockerfile was written but not built in this session;
  Docker execution is a pipeline responsibility.

### Fallbacks if a harness fails to compile in the pipeline

If a symbol resolution issue appears at link time — for example because a
target static function was renamed in a point release — the pipeline job is
expected to:

1. Record the failing harness and the missing symbol.
2. Skip that harness for the current run (do not silently fall back to a
    dummy target).
3. Open a finding so the harness can be updated.

The harnesses are intentionally the primary source of truth for CVE-class
surface coverage in this lab branch; silently replacing them would invalidate
the experimental measurement.

## Reproducible build

### Why a dedicated Dockerfile

Binary analysis (checksec, hardening, symbol / string inventory) is sensitive
to compiler version, libc version, and link flags. A reproducible-build helper
that pins Ubuntu 22.04 and builds OpenSSL 1.1.1u from source gives the
pipeline a stable ELF to analyse, independent of whatever runners Jenkins
happens to allocate.

This is **not** the main tool-execution environment. It is a single-purpose
image that emits one artefact into `.lab/docker/output/mosquitto`.

### Hardening flags

The Dockerfile sets `CFLAGS` with `-fstack-protector-strong`,
`-D_FORTIFY_SOURCE=2`, `-fPIE`, and link flags `-Wl,-z,relro -Wl,-z,now
-pie`. These are intentionally reasonable rather than maximal: the pipeline's
binary analysis phase should *detect* their presence / absence; making them
maximal would collapse the detection signal.

## SCA enrichment — vendor manifest

### Why a hand-curated CycloneDX vendor manifest

Automated SBOM tools (Syft, Snyk `--unmanaged`) were unable to detect any of
Mosquitto's vendored C/C++ components during the lab validation phase:

- **Syft** produced an SBOM with 0 C/C++ components. Syft's detection model is
  manifest-driven (`package.json`, `go.sum`, `Cargo.lock`, …). There is no
  manifest for header-only or source-vendored C libraries. This is a structural
  limitation, not a configuration error.
- **Snyk `--unmanaged`** reported 0 dependencies and 0 vulnerabilities against
  `.lab/vendor/cjson-1.7.14/`. Snyk's source fingerprinting database did not
  produce a match against the cJSON 1.7.14 source files during testing.
- **Grype** (fed the Syft SBOM) consequently also found 0 matches.

This is the canonical SCA blind spot for embedded C/C++ projects. The industry
practice — documented by NTIA, CISA, and the OpenChain/SPDX working groups —
is to supplement automated tooling with a hand-curated manifest that declares
the components the tooling cannot discover.

### What the manifest covers

`.lab/sca/vendor-manifest.cdx.json` (CycloneDX 1.4) declares three components
identified by manual inspection of the source tree:

| Component | Version | Location | Detection method |
|-----------|---------|----------|------------------|
| uthash    | 2.1.0   | `deps/uthash.h` | header comment + GitHub tag |
| utlist    | 2.1.0   | `deps/utlist.h` | header comment + GitHub tag |
| cJSON     | 1.7.14  | `.lab/vendor/cjson-1.7.14/` + `snap/snapcraft.yaml` | explicit version in snapcraft source entry |

Each component carries a `purl` (Package URL) so that downstream vulnerability
scanners (Grype, OSV-Scanner) can look up matching CVEs.

### How the manifest integrates into the pipeline

`05_validate_sca_grype.sh` performs two sequential scans:

1. **Scan 1** — Syft SBOM (`sbom-cyclonedx.json`): validates that Grype runs
   correctly and reflects the automated tooling result. Expected result: 0 or
   very few matches.
2. **Scan 2** — vendor manifest (`vendor-manifest.cdx.json`): queries Grype
   against the curated component list. Expected result: CVE matches for
   cJSON 1.7.14 (if the version has known advisories in the Grype database).

The two scan results are saved separately so the pipeline can report both the
automated blind spot and the enriched finding side by side.

### Why this is a TFG-level finding, not just a workaround

The inability of three state-of-the-art SCA tools to detect vendored C/C++
dependencies from source alone is itself a pipeline-risk finding. Documenting
the gap and closing it with a vendor manifest is the recommended remediation.
This demonstrates the full DevSecOps cycle: detect → understand → remediate →
validate.

## Deviations from the requested plan

None that change semantics. Noted details:

- `.lab/fuzzing/build/`, `.lab/fuzzing/findings/libfuzzer/`,
  `.lab/fuzzing/findings/afl/`, `.lab/fuzzing/coverage/`, and
  `.lab/docker/output/` are created at script run-time rather than committed
  as empty directories. This is consistent with `.lab/.gitignore`, which
  ignores all of them. The structure diagram lists them as output locations;
  they should not be tracked.
- The existing empty repository at
  `c:/Users/mario/Desktop/INFORMATICA/4º Curso/TFG/mosquitto-proyecto-base/mosquitto-proyecto-base`
  was reused as the working copy. The Mosquitto upstream was added as a
  remote named `mosquitto`, tag `v2.0.18` was fetched, and
  `exp/mosquitto-v2.0.18-upstream` / `exp/mosquitto-v2.0.18-lab` were created
  from it. The pre-existing `main` branch carried no commits and was not
  retained.
